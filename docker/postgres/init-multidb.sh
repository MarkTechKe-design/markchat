#!/bin/bash
set -e

echo "[PostgreSQL Multi-DB Init] Checking and creating MarkChat databases..."

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    SELECT 'CREATE DATABASE markchat_bridge_production'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'markchat_bridge_production')\gexec

    GRANT ALL PRIVILEGES ON DATABASE markchat_bridge_production TO "$POSTGRES_USER";
EOSQL

echo "[PostgreSQL Multi-DB Init] markchat_bridge_production initialized successfully."
