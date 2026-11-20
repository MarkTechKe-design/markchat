# MarkChat — Security Remediation & Deployment Operations Guide

- **Classification:** MarkChat Operational Reference
- **Engine Baseline:** Chatwoot CE v4.19 (`af2a870c6d`)
- **SMS Microservice:** Fastify Node.js Bridge (`C:\Development\markchat-sms-bridge`)

---

## 1. Overview of Completed Remediations

| Finding | Area | Status | Ownership | Solution Implemented |
|---|---|---|---|---|
| **SEC-009** | Webhook Auth | **Remediated** | Bridge-owned | Mandatory `WEBHOOK_SECRET` validation via `timingSafeEqual` over SHA-256 digests. Missing or invalid tokens fail closed with HTTP 401. |
| **SEC-010** | Admin Secrets | **Remediated** | Bridge-owned | Eliminated `?key=` query parameters and form URLs. Implemented dedicated `/superadmin/login` with AES-256-GCM encrypted HttpOnly session cookies, per-session CSRF tokens, and IP brute-force lockout. |
| **SEC-011** | Suspension | **Mitigated** | Upstream / Bridge | Upstream code preserved untouched. Implemented edge telephony enforcement rejecting inbound/outbound traffic for suspended tenants; documented upstream PR specification. |
| **SEC-012** | Multi-Tenancy | **Remediated** | Bridge-owned | Added `inbox_id` and `inbound_address` to `tenants` table. Inbound routing resolves strictly server-side by destination phone/shortcode. External payload `account_id`/`inbox_id` spoofing completely eliminated. |
| **SEC-013** | Credit Ledger | **Remediated** | Bridge-owned | Implemented atomic credit deduction, automated refund on provider dispatch failure with transaction tracking, and explicit timeout handling to prevent duplicate charges or free messages. |
| **PG-Init** | Dual-DB Setup | **Remediated** | Config-owned | Added `docker/postgres/init-multidb.sh` mounted via `docker-compose.override.yaml` for fresh volumes; created idempotent `scripts/provision-bridge-db.sh` for existing volumes. |
| **Backup** | Backup Security| **Remediated** | Config-owned | Built streaming GPG encryption pipeline (`scripts/backup-database.sh`) eliminating plaintext disk writes and restricting offsite sync to `*.dump.gpg` and `checksums_*.sha256`. |

---

## 2. Environment Variables & Secret Configuration

### A. Primary Engine (`.env`)
```bash
# Core Chatwoot Settings
RAILS_ENV=production
INSTALLATION_ENV=docker
SECRET_KEY_BASE=<high-entropy-64-byte-hex>
FRONTEND_URL=https://app.markchat.co.ke
PORT=3000

# PostgreSQL (Chatwoot Primary Database)
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DB=chatwoot
POSTGRES_USER=postgres
POSTGRES_PASSWORD=<strong-random-password>

# Redis
REDIS_URL=redis://default:<strong-redis-password>@redis:6379/0

# Internal Webhook Authorization
ALLOW_INTERNALLY_HOSTED_WEBHOOKS=true
SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true
```

### B. SMS Bridge (`../markchat-sms-bridge/.env`)
```bash
PORT=4000
MARKCHAT_BASE_URL=http://rails:3000
MARKCHAT_ACCOUNT_ID=2
MARKCHAT_API_TOKEN=<chatwoot-account-api-token>
MARKCHAT_PLATFORM_TOKEN=<chatwoot-platform-admin-token>
MARKCHAT_ADMIN_USER_ID=1

# Superadmin & Session Encryption (AES-256-GCM)
SUPERADMIN_SECRET=<high-entropy-admin-passkey>
ENCRYPTION_KEY=<64-char-hex-encryption-key>
WEBHOOK_SECRET=<high-entropy-shared-webhook-secret>

# PostgreSQL (Bridge Database - Co-located on same DB instance)
BRIDGE_DATABASE_URL=postgres://postgres:<strong-random-password>@postgres:5432/markchat_bridge_production

# Telecom Provider (Africa's Talking / Sandbox / Live)
AT_USERNAME=sandbox
AT_API_KEY=<africas-talking-api-key>
AT_SENDER_ID=
```

---

## 3. Deployment & Operational Runbook

### 3.1 Fresh Deployment (Clean Server)
1. Ensure `docker-compose.production.yaml` and `docker-compose.override.yaml` are present.
2. Initialize Docker stack:
   ```bash
   docker compose -f docker-compose.production.yaml -f docker-compose.override.yaml up -d postgres redis
   ```
   PostgreSQL automatically executes `/docker-entrypoint-initdb.d/init-multidb.sh`, creating both `chatwoot` and `markchat_bridge_production`.
3. Launch remaining services:
   ```bash
   docker compose -f docker-compose.production.yaml -f docker-compose.override.yaml up -d
   ```

### 3.2 Existing Volume Migration
If deploying against an existing PostgreSQL data volume where `init-multidb.sh` will not automatically trigger:
```bash
./scripts/provision-bridge-db.sh
```

---

## 4. Superadmin Access & Session Management
- **Console URL:** `http://localhost:4000/superadmin/login`
- Enter `SUPERADMIN_SECRET`.
- Upon successful authentication, an encrypted `mc_admin_session` cookie is issued.
- Form submissions use anti-CSRF tokens.
- All URL parameters and redirects are secret-free.
