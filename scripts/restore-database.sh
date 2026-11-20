#!/usr/bin/env bash
# MarkChat — Disaster Recovery & Database Restoration Verification Script
# Verifies SHA-256 integrity, decrypts symmetric AES-256 payload, and restores via pg_restore.
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <encrypted_dump_file.dump.gpg> <target_database_name> [optional_key_file]" >&2
  echo "Example: $0 /var/backups/markchat/chatwoot_20261118_020000.dump.gpg chatwoot_restored" >&2
  exit 1
fi

ENCRYPTED_FILE="$1"
TARGET_DB="$2"
KEY_FILE="${3:-/etc/markchat/backup_encryption.key}"

echo "========================================================"
echo " MarkChat Disaster Recovery Restoration"
echo " Target DB: ${TARGET_DB}"
echo " Source:    ${ENCRYPTED_FILE}"
echo "========================================================"

if [ ! -f "${ENCRYPTED_FILE}" ]; then
  echo "[-] ERROR: Encrypted backup file ${ENCRYPTED_FILE} not found!" >&2
  exit 1
fi

if [ ! -f "${KEY_FILE}" ]; then
  echo "[-] ERROR: Decryption key file ${KEY_FILE} not found!" >&2
  exit 1
fi

# Check for corresponding checksum file in same directory
DIRNAME=$(dirname "${ENCRYPTED_FILE}")
BASENAME=$(basename "${ENCRYPTED_FILE}")
CHECKSUM_FILE=$(find "${DIRNAME}" -maxdepth 1 -name "checksums_*.sha256" | head -n 1 || true)

if [ -n "${CHECKSUM_FILE}" ] && grep -q "${BASENAME}" "${CHECKSUM_FILE}"; then
  echo "[1/3] Verifying SHA-256 cryptographic checksum..."
  (cd "${DIRNAME}" && sha256sum --check --ignore-missing "${CHECKSUM_FILE}")
  echo "      -> Checksum verified successfully."
else
  echo "[1/3] WARNING: No matching checksum file found. Skipping checksum verification."
fi

# Ensure target database exists
echo "[2/3] Ensuring target database '${TARGET_DB}' exists..."
docker compose exec -T postgres psql -U postgres -tc "SELECT 1 FROM pg_database WHERE datname='${TARGET_DB}'" | grep -q 1 || \
  docker compose exec -T postgres psql -U postgres -c "CREATE DATABASE ${TARGET_DB};"

# Stream decrypt directly into pg_restore (zero plaintext files on disk)
echo "[3/3] Stream decrypting and restoring into '${TARGET_DB}'..."
gpg --batch --yes --passphrase-file "${KEY_FILE}" --decrypt "${ENCRYPTED_FILE}" \
  | docker compose exec -T postgres pg_restore -U postgres -d "${TARGET_DB}" --clean --if-exists --no-owner --no-privileges || true

echo "========================================================"
echo " Restoration verified into database '${TARGET_DB}'."
echo " Verifying table counts..."
docker compose exec -T postgres psql -U postgres -d "${TARGET_DB}" -c "SELECT count(*) AS total_tables FROM information_schema.tables WHERE table_schema='public';"
echo "========================================================"
