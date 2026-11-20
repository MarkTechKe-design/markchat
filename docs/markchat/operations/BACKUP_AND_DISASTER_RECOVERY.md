# MarkChat — Hardened Backup & Disaster Recovery Architecture

- **Classification:** MarkChat Operational Standard
- **Target Environments:** VPS (Free/Paid), Docker Compose Deployments
- **Security Standard:** Zero-Plaintext Storage, AES-256 Symmetric Encryption, SHA-256 Verification

---

## 1. Overview & Threat Model

Traditional database backup procedures that dump PostgreSQL to a `.dump` file and then encrypt it leave unencrypted plaintext files on local disk. If an automated script executes a wildcard copy (`rclone copy /backup/ ...`), both the encrypted `.dump.gpg` and the unencrypted `.dump` are transferred offsite, completely exposing customer data and database credentials.

MarkChat's hardened backup pipeline enforces **streaming encryption directly from `pg_dump` into `gpg`**, ensuring that unencrypted dumps never touch local block storage or upload queues.

---

## 2. Backup Pipeline Architecture

```
+-------------------+      STDOUT Stream      +-------------------+      Encrypted File      +-----------------------+
|  docker compose   | ---------------------> |        gpg        | --------------------> | /var/backups/markchat |
|  exec pg_dump -Fc |   (Zero disk writes)   |  (AES-256-GCM)    |   (chmod 600)         |   chatwoot_*.dump.gpg |
+-------------------+                        +-------------------+                       |   bridge_*.dump.gpg   |
                                                                                         +-----------------------+
                                                                                                     |
                                                                                            rclone copy --include
                                                                                                     v
                                                                                         +-----------------------+
                                                                                         | Remote Cloud Storage  |
                                                                                         | (Cloudflare R2/S3/B2) |
                                                                                         +-----------------------+
```

### Key Security Safeguards
1. **Zero Plaintext on Disk:** Standard output from `pg_dump` is piped directly to `gpg`. No temporary plaintext files are created.
2. **Restrictive File System Permissions:** Backup directory is locked to `chmod 700`, files to `chmod 600`.
3. **Cryptographic Checksumming:** SHA-256 checksums are generated for each encrypted archive and stored in `checksums_*.sha256`.
4. **Strict Allowlist Uploading:** `rclone` is restricted via `--include "*.dump.gpg"` and `--include "checksums_*.sha256"`.
5. **Local Retention Lifecycle:** Local encrypted archives are automatically purged after 3 days.

---

## 3. Encryption Key Management & Recovery Strategy

The symmetric GPG key file (`/etc/markchat/backup_encryption.key`) must be protected under strict operational separation:

- **Key Generation:**
  ```bash
  openssl rand -base64 32 > /etc/markchat/backup_encryption.key
  chmod 600 /etc/markchat/backup_encryption.key
  ```
- **Off-Host Escrow:**
  The backup encryption key **must never reside solely on the production VPS**. It must be archived in an offline password vault (e.g. Bitwarden, 1Password) or an independent cloud KMS. If the VPS is destroyed or reclaimed, the key in the vault is required to restore the offsite `.dump.gpg` files.
- **Separation of Concerns:**
  The credentials used for `rclone` (cloud storage bucket access) and the GPG encryption key must be completely decoupled. Access to the backup bucket alone does not permit reading customer data.

---

## 4. Disaster Recovery & Restoration Procedure

To verify or execute disaster recovery on a fresh machine:

1. **Verify Checksum:**
   ```bash
   cd /var/backups/markchat
   sha256sum --check --ignore-missing checksums_YYYYMMDD_HHMMSS.sha256
   ```
2. **Execute Restoration Script:**
   ```bash
   ./scripts/restore-database.sh /var/backups/markchat/chatwoot_YYYYMMDD_HHMMSS.dump.gpg chatwoot /etc/markchat/backup_encryption.key
   ./scripts/restore-database.sh /var/backups/markchat/bridge_YYYYMMDD_HHMMSS.dump.gpg markchat_bridge_production /etc/markchat/backup_encryption.key
   ```
3. **Restoration Drill Cadence:**
   A full restoration drill into an isolated staging database must be conducted once per quarter.
