#!/usr/bin/env bash
# MarkChat — Standalone Idempotent Database Provisioner for Existing Volumes
# Safe to run against a running PostgreSQL container without restarting or wiping data.
set -euo pipefail

echo "==> Verifying markchat_bridge_production database..."

DB_EXISTS=$(docker compose exec -T postgres psql -U postgres -tAc "SELECT 1 FROM pg_database WHERE datname='markchat_bridge_production'")

if [ "$DB_EXISTS" = "1" ]; then
  echo "==> Database 'markchat_bridge_production' already exists. Skipping creation."
else
  echo "==> Creating database 'markchat_bridge_production'..."
  docker compose exec -T postgres psql -U postgres -c "CREATE DATABASE markchat_bridge_production;"
  docker compose exec -T postgres psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE markchat_bridge_production TO postgres;"
  echo "==> Database 'markchat_bridge_production' created successfully."
fi

echo "==> Dual-database configuration verified."
