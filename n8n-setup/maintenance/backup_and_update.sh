#!/usr/bin/env bash
# This script automates the backup, update, and restart process for the n8n stack.
# It ensures that n8n data is regularly backed up and that the running containers are up-to-date.
set -euo pipefail
# Change to the directory containing the docker-compose.yml file.
cd "$(dirname "$0")/.."
# Generate a timestamp for the backup filename.
timestamp=$(date -u +%Y%m%d-%H%M%S)
# Define the backup file path.
backup="backups/n8n-backup-$timestamp.tar.gz"

echo "[*] Backing up n8n data to $backup"
# Create a compressed tar archive of the n8n data directory.
tar -czf "$backup" n8n/data

echo "[*] Pulling latest images"
# Pull the latest Docker images as defined in docker-compose.yml.
podman-compose pull

echo "[*] Restarting stack"
# Restart the n8n and Caddy containers in detached mode.
podman-compose up -d

echo "[*] Pruning old backups (keep 8)"
# List backups, sort by modification time (newest first), skip the first 8, and remove the rest.
ls -1t backups/n8n-backup-*.tar.gz 2>/dev/null | tail -n +9 | xargs -r rm -f

echo "[*] Done"
