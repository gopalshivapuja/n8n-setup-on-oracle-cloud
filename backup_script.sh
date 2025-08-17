#!/bin/bash

# n8n Automated Backup Script
# Author: Gopal Shivapuja
# Description: Creates comprehensive backups of n8n installation

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
BACKUP_BASE_DIR="$PROJECT_ROOT/backups"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=30

# Load environment variables
if [[ -f "$PROJECT_ROOT/.env" ]]; then
    source "$PROJECT_ROOT/.env"
fi

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Check if n8n is running
check_n8n_status() {
    if ! podman ps | grep -q "n8n"; then
        warning "n8n container is not running. Some backups may be incomplete."
        return 1
    fi
    return 0
}

# Create backup directory structure
setup_backup_dir() {
    local backup_dir="$BACKUP_BASE_DIR/daily/$DATE"
    mkdir -p "$backup_dir"
    echo "$backup_dir"
}

# Backup n8n workflows
backup_workflows() {
    local backup_dir="$1"
    
    log "Backing up n8n workflows..."
    
    if check_n8n_status; then
        # Export all workflows
        if podman exec n8n n8n export:workflow --all --output="/home/node/.n8n/backups/workflows_$DATE.json" 2>/dev/null; then
            # Copy from container to backup directory
            podman cp n8n:/home/node/.n8n/backups/workflows_$DATE.json "$backup_dir/"
            info "✅ Workflows exported successfully"
        else
            warning "Failed to export workflows - n8n may be empty or unreachable"
        fi
        
        # Export credentials (encrypted)
        if podman exec n8n n8n export:credentials --all --output="/home/node/.n8n/backups/credentials_$DATE.json" 2>/dev/null; then
            podman cp n8n:/home/node/.n8n/backups/credentials_$DATE.json "$backup_dir/"
            info "✅ Credentials exported successfully"
        else
            warning "Failed to export credentials"
        fi
    fi
}

# Backup PostgreSQL database
backup_database() {
    local backup_dir="$1"
    
    log "Backing up PostgreSQL database..."
    
    if podman ps | grep -q "postgres"; then
        # Create database backup
        if podman exec postgres pg_dump -U "${POSTGRES_USER:-n8n}" "${POSTGRES_DB:-n8n}" | gzip > "$backup_dir/database_$DATE.sql.gz"; then
            info "✅ Database backup created: $(du -h "$backup_dir/database_$DATE.sql.gz" | cut -f1)"
        else
            error "Failed to backup database"
        fi
        
        # Backup database configuration
        podman exec postgres pg_dumpall -U "${POSTGRES_USER:-n8n}" --globals-only | gzip > "$backup_dir/database_globals_$DATE.sql.gz"
    else
        warning "PostgreSQL container not running - skipping database backup"
    fi
}

# Backup file system data
backup_filesystem() {
    local backup_dir="$1"
    
    log "Backing up filesystem data..."
    
    # Backup n8n data directory
    if [[ -d "$PROJECT_ROOT/data/n8n" ]]; then
        tar -czf "$backup_dir/n8n_data_$DATE.tar.gz" -C "$PROJECT_ROOT" data/n8n/
        info "✅ n8n data backup created: $(du -h "$backup_dir/n8n_data_$DATE.tar.gz" | cut -f1)"
    fi
    
    # Backup configuration files
    tar -czf "$backup_dir/config_$DATE.tar.gz" -C "$PROJECT_ROOT" \
        config/ \
        .env \
        docker-compose*.yml 2>/dev/null || true
    
    # Backup SSL certificates if they exist
    if [[ -d "$PROJECT_ROOT/data/nginx/ssl" ]]; then
        tar -czf "$backup_dir/ssl_certificates_$DATE.tar.gz" -C "$PROJECT_ROOT" data/nginx/ssl/
        info "✅ SSL certificates backed up"
    fi
}

# Create backup metadata
create_backup_metadata() {
    local backup_dir="$1"
    
    log "Creating backup metadata..."
    
    cat > "$backup_dir/backup_info.json" << EOF
{
    "backup_date": "$(date -Iseconds)",
    "backup_type": "automated_daily",
    "n8n_version": "$(podman exec n8n n8n --version 2>/dev/null || echo 'unknown')",
    "postgres_version": "$(podman exec postgres postgres --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1 || echo 'unknown')",
    "system_info": {
        "hostname": "$(hostname)",
        "os": "$(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"')",
        "arch": "$(uname -m)",
        "kernel": "$(uname -r)"
    },
    "backup_contents": {
        "workflows": $([ -f "$backup_dir/workflows_$DATE.json" ] && echo "true" || echo "false"),
        "credentials": $([ -f "$backup_dir/credentials_$DATE.json" ] && echo "true" || echo "false"),
        "database": $([ -f "$backup_dir/database_$DATE.sql.gz" ] && echo "true" || echo "false"),
        "filesystem": $([ -f "$backup_dir/n8n_data_$DATE.tar.gz" ] && echo "true" || echo "false"),
        "configuration": $([ -f "$backup_dir/config_$DATE.tar.gz" ] && echo "true" || echo "false"),
        "ssl_certificates": $([ -f "$backup_dir/ssl_certificates_$DATE.tar.gz" ] && echo "true" || echo "false")
    },
    "backup_sizes": {
$(find "$backup_dir" -name "*.gz" -o -name "*.json" | while read -r file; do
    echo "        \"$(basename "$file")\": \"$(du -h "$file" | cut -f1)\","
done | sed '$ s/,$//')
    }
}
EOF
    
    info "✅ Backup metadata created"
}

# Verify backup integrity
verify_backup() {
    local backup_dir="$1"
    
    log "Verifying backup integrity..."
    
    local error_count=0
    
    # Check if backup files exist and are not empty
    for file in "$backup_dir"/*.gz "$backup_dir"/*.json; do
        if [[ -f "$file" ]]; then
            if [[ ! -s "$file" ]]; then
                warning "Backup file is empty: $(basename "$file")"
                ((error_count++))
            fi
        fi
    done
    
    # Test gzip files
    for file in "$backup_dir"/*.gz; do
        if [[ -f "$file" ]]; then
            if ! gzip -t "$file" 2>/dev/null; then
                warning "Corrupted gzip file: $(basename "$file")"
                ((error_count++))
            fi
        fi
    done
    
    # Test JSON files
    for file in "$backup_dir"/*.json; do
        if [[ -f "$file" ]]; then
            if ! python3 -m json.tool "$file" >/dev/null 2>&1; then
                warning "Invalid JSON file: $(basename "$file")"
                ((error_count++))
            fi
        fi
    done
    
    if [[ $error_count -eq 0 ]]; then
        info "✅ Backup verification passed"
        return 0
    else
        warning "⚠️ Backup verification found $error_count issues"
        return 1
    fi
}

# Cleanup old backups
cleanup_old_backups() {
    log "Cleaning up old backups (older than $RETENTION_DAYS days)..."
    
    local deleted_count=0
    
    find "$BACKUP_BASE_DIR/daily" -type d -name "[0-9]*_[0-9]*" -mtime +$RETENTION_DAYS | while read -r old_backup; do
        if [[ -d "$old_backup" ]]; then
            rm -rf "$old_backup"
            ((deleted_count++))
            info "Deleted old backup: $(basename "$old_backup")"
        fi
    done
    
    if [[ $deleted_count -gt 0 ]]; then
        info "✅ Cleaned up $deleted_count old backups"
    else
        info "No old backups to clean up"
    fi
}

# Upload to Oracle Object Storage (optional)
upload_to_oci() {
    local backup_dir="$1"
    
    if [[ -n "${OCI_BUCKET_NAME:-}" ]] && command -v oci >/dev/null 2>&1; then
        log "Uploading backup to Oracle Object Storage..."
        
        # Create compressed archive of entire backup
        local archive_name="n8n_backup_$DATE.tar.gz"
        tar -czf "/tmp/$archive_name" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"
        
        # Upload to OCI
        if oci os object put \
            --bucket-name "${OCI_BUCKET_NAME}" \
            --file "/tmp/$archive_name" \
            --name "daily/$archive_name" \
            --region "${OCI_REGION:-us-ashburn-1}" >/dev/null 2>&1; then
            info "✅ Backup uploaded to OCI Object Storage"
            rm "/tmp/$archive_name"
        else
            warning "Failed to upload backup to OCI Object Storage"
        fi
    fi
}

# Send notification (optional)
send_notification() {
    local backup_dir="$1"
    local status="$2"
    
    if [[ -n "${NOTIFICATION_WEBHOOK:-}" ]]; then
        local backup_size=$(du -sh "$backup_dir" | cut -f1)
        local message="n8n Backup $status - Size: $backup_size - Date: $DATE"
        
        curl -X POST "$NOTIFICATION_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d "{\"text\": \"$message\"}" >/dev/null 2>&1 || true
    fi
}

# Generate backup report
generate_report() {
    local backup_dir="$1"
    
    log "Generating backup report..."
    
    local report_file="$backup_dir/backup_report.txt"
    
    cat > "$report_file" << EOF
n8n Backup Report
=================

Date: $(date)
Backup Directory: $backup_dir
Retention Policy: $RETENTION_DAYS days

Backup Contents:
$(ls -lh "$backup_dir")

Total Backup Size: $(du -sh "$backup_dir" | cut -f1)

System Information:
- Hostname: $(hostname)
- OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')
- Architecture: $(uname -m)
- Available Space: $(df -h "$BACKUP_BASE_DIR" | tail -1 | awk '{print $4}')

Container Status:
$(podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Size}}")

Recent Backup History:
$(find "$BACKUP_BASE_DIR/daily" -maxdepth 1 -type d -name "[0-9]*_[0-9]*" | sort -r | head -5 | while read -r dir; do
    echo "$(basename "$dir"): $(du -sh "$dir" | cut -f1)"
done)
EOF
    
    info "✅ Backup report generated"
}

# Main backup function
main() {
    log "Starting n8n backup process..."
    
    # Setup
    local backup_dir
    backup_dir=$(setup_backup_dir)
    
    # Perform backups
    backup_workflows "$backup_dir"
    backup_database "$backup_dir"
    backup_filesystem "$backup_dir"
    
    # Create metadata and verify
    create_backup_metadata "$backup_dir"
    
    if verify_backup "$backup_dir"; then
        log "✅ Backup completed successfully!"
        generate_report "$backup_dir"
        send_notification "$backup_dir" "SUCCESS"
        
        # Optional: upload to cloud storage
        upload_to_oci "$backup_dir"
        
        # Cleanup old backups
        cleanup_old_backups
        
        info "Backup location: $backup_dir"
        info "Total backup size: $(du -sh "$backup_dir" | cut -f1)"
        
    else
        error "❌ Backup verification failed!"
        send_notification "$backup_dir" "FAILED"
        exit 1
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi