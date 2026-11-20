#!/usr/bin/env bash
# MarkChat — Hardened Streaming Encrypted Database Backup Pipeline
# Enforces AES-256-GCM symmetric encryption directly from pg_dump stream.
# Plaintext database dumps NEVER touch local disk or upload staging.
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/var/backups/markchat}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
KEY_FILE="${BACKUP_KEY_FILE:-/etc/markchat/backup_encryption.key}"
RCLONE_REMOTE="${RCLONE_REMOTE:-}" # e.g. remote-encrypted:markchat-backups

echo "========================================================"
echo " MarkChat Secure Database Backup: ${TIMESTAMP}"
echo "========================================================"

# Pre-flight security validations
if [ ! -f "${KEY_FILE}" ]; then
  echo "[-] ERROR: Backup encryption key file not found at ${KEY_FILE}!" >&2
  echo "    Generate a high-entropy key with: openssl rand -base64 32 > ${KEY_FILE} && chmod 600 ${KEY_FILE}" >&2
  exit 1
fi

mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}"

CHATWOOT_ENCRYPTED="${BACKUP_DIR}/chatwoot_${TIMESTAMP}.dump.gpg"
BRIDGE_ENCRYPTED="${BACKUP_DIR}/bridge_${TIMESTAMP}.dump.gpg"
CHECKSUM_FILE="${BACKUP_DIR}/checksums_${TIMESTAMP}.sha256"

# 1. Stream Chatwoot database dump directly into GPG (AES-256 symmetric)
echo "[1/4] Dumping and streaming 'chatwoot' database direct to encrypted artifact..."
docker compose exec -T postgres pg_dump -U postgres -d chatwoot -Fc \
  | gpg --batch --yes --passphrase-file "${KEY_FILE}" --symmetric --cipher-algo AES256 \
  -o "${CHATWOOT_ENCRYPTED}"
chmod 600 "${CHATWOOT_ENCRYPTED}"
echo "      -> Created ${CHATWOOT_ENCRYPTED}"

# 2. Stream Bridge database dump directly into GPG (AES-256 symmetric)
echo "[2/4] Dumping and streaming 'markchat_bridge_production' database direct to encrypted artifact..."
docker compose exec -T postgres pg_dump -U postgres -d markchat_bridge_production -Fc \
  | gpg --batch --yes --passphrase-file "${KEY_FILE}" --symmetric --cipher-algo AES256 \
  -o "${BRIDGE_ENCRYPTED}"
chmod 600 "${BRIDGE_ENCRYPTED}"
echo "      -> Created ${BRIDGE_ENCRYPTED}"

# 3. Generate SHA-256 checksums of encrypted artifacts
echo "[3/4] Computing SHA-256 checksums for encrypted artifacts..."
(cd "${BACKUP_DIR}" && sha256sum "chatwoot_${TIMESTAMP}.dump.gpg" "bridge_${TIMESTAMP}.dump.gpg" > "${CHECKSUM_FILE}")
chmod 600 "${CHECKSUM_FILE}"
echo "      -> SHA-256 signatures generated."

# 4. Offsite Transfer (Only if RCLONE_REMOTE is configured)
if [ -n "${RCLONE_REMOTE}" ]; then
  echo "[4/4] Uploading ONLY encrypted artifacts and checksums to offsite storage..."
  rclone copy --include "*.dump.gpg" --include "checksums_*.sha256" "${BACKUP_DIR}/" "${RCLONE_REMOTE}/"
  echo "      -> Offsite replication complete."
else
  echo "[4/4] Offsite transfer skipped (RCLONE_REMOTE not set). Encrypted backups retained locally."
fi

# 5. Local Retention: Purge local artifacts older than 3 days
echo "[-] Pruning local backup artifacts older than 3 days..."
find "${BACKUP_DIR}" -name "*.dump.gpg" -mtime +3 -delete || true
find "${BACKUP_DIR}" -name "checksums_*.sha256" -mtime +3 -delete || true

echo "========================================================"
echo " Backup pipeline completed successfully at $(date)"
echo " Zero plaintext files generated."
echo "========================================================"
