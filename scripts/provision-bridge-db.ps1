# MarkChat — Standalone Idempotent Database Provisioner for Existing Volumes (PowerShell)
$ErrorActionPreference = "Stop"

Write-Host "==> Verifying markchat_bridge_production database..." -ForegroundColor Cyan

$dbExists = docker compose exec -T postgres psql -U postgres -tAc "SELECT 1 FROM pg_database WHERE datname='markchat_bridge_production'"

if ($dbExists.Trim() -eq "1") {
    Write-Host "==> Database 'markchat_bridge_production' already exists. Skipping creation." -ForegroundColor Green
} else {
    Write-Host "==> Creating database 'markchat_bridge_production'..." -ForegroundColor Yellow
    docker compose exec -T postgres psql -U postgres -c "CREATE DATABASE markchat_bridge_production;"
    docker compose exec -T postgres psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE markchat_bridge_production TO postgres;"
    Write-Host "==> Database 'markchat_bridge_production' created successfully." -ForegroundColor Green
}

Write-Host "==> Dual-database configuration verified." -ForegroundColor Cyan
