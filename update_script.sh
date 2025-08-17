#!/bin/bash

# n8n Automated Update Script
# Author: Gopal Shivapuja
# Description: Safely updates n8n with backup and rollback capability

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
DATE=$(date +%Y%m%d_%H%M%S)
UPDATE_LOG="$PROJECT_ROOT/logs/update_$DATE.log"

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
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    echo -e "${GREEN}$message${NC}" | tee -a "$UPDATE_LOG"
}

error() {
    local message="[ERROR] $1"
    echo -e "${RED}$message${NC}" | tee -a "$UPDATE_LOG"
    exit 1
}

warning() {
    local message="[WARNING] $1"
    echo -e "${YELLOW}$message${NC}" | tee -a "$UPDATE_LOG"
}

info() {
    local message="[INFO] $1"
    echo -e "${BLUE}$message${NC}" | tee -a "$UPDATE_LOG"
}

# Create logs directory
mkdir -p "$PROJECT_ROOT/logs"

# Check if services are running
check_services() {
    log "Checking service status..."
    
    if ! podman ps | grep -q "n8n"; then
        error "n8n container is not running. Please start it first."
    fi
    
    info "✅ n8n is running"
}

# Get current n8n version
get_current_version() {
    local current_version
    current_version=$(podman exec n8n n8n --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
    echo "$current_version"
}

# Get latest n8n version
get_latest_version() {
    local latest_version
    latest_version=$(curl -s https://api.github.com/repos/n8n-io/n8n/releases/latest | grep -oE '"tag_name": *"[^"]*"' | cut -d'"' -f4 | sed 's/^n8n@//' || echo "unknown")
    echo "$latest_version"
}

# Create pre-update backup
create_backup() {
    log "Creating pre-update backup..."
    
    local backup_dir="$PROJECT_ROOT/backups/updates/pre_update_$DATE"
    mkdir -p "$backup_dir"
    
    # Run backup script
    if [[ -f "$SCRIPT_DIR/backup-n8n.sh" ]]; then
        # Temporary backup for update
        BACKUP_BASE_DIR="$PROJECT_ROOT/backups/updates" "$SCRIPT_DIR/backup-n8n.sh"
        
        # Move to update-specific location
        if [[ -d "$PROJECT_ROOT/backups/updates/daily" ]]; then
            local latest_backup=$(find "$PROJECT_ROOT/backups/updates/daily" -name "[0-9]*_[0-9]*" -type d | sort -r | head -1)
            if [[ -n "$latest_backup" ]]; then
                mv "$latest_backup" "$backup_dir/backup_data"
                info "✅ Pre-update backup created: $backup_dir"
                echo "$backup_dir"
                return 0
            fi
        fi
    fi
    
    error "Failed to create pre-update backup"
}

# Check for available updates
check_for_updates() {
    log "Checking for n8n updates..."
    
    local current_version
    local latest_version
    
    current_version=$(get_current_version)
    latest_version=$(get_latest_version)
    
    info "Current version: $current_version"
    info "Latest version: $latest_version"
    
    if [[ "$current_version" == "unknown" ]] || [[ "$latest_version" == "unknown" ]]; then
        warning "Unable to determine version information"
        return 1
    fi
    
    if [[ "$current_version" == "$latest_version" ]]; then
        info "n8n is already up to date"
        return 1
    fi
    
    return 0
}

# Health check function
health_check() {
    local max_attempts=30
    local attempt=1
    
    log "Performing health check..."
    
    while [[ $attempt -le $max_attempts ]]; do
        if podman exec n8n wget --spider -q http://localhost:5678/healthz 2>/dev/null; then
            info "✅ Health check passed (attempt $attempt)"
            return 0
        fi
        
        info "Health check attempt $attempt/$max_attempts failed, waiting..."
        sleep 10
        ((attempt++))
    done
    
    error "Health check failed after $max_attempts attempts"
}

# Update system packages
update_system() {
    log "Updating system packages..."
    
    # Update Oracle Linux packages
    sudo dnf update -y
    
    # Update Podman if available
    sudo dnf update -y podman podman-compose
    
    info "✅ System packages updated"
}

# Pull latest images
pull_latest_images() {
    log "Pulling latest container images..."
    
    # Determine which compose file to use
    local compose_file
    if [[ -f "$PROJECT_ROOT/config/docker-compose.production.yml" ]] && podman ps | grep -q "postgres\|nginx"; then
        compose_file="config/docker-compose.production.yml"
    else
        compose_file="config/docker-compose.basic.yml"
    fi
    
    # Pull latest images
    cd "$PROJECT_ROOT"
    podman-compose -f "$compose_file" pull
    
    info "✅ Latest images pulled"
    echo "$compose_file"
}

# Restart services with new images
restart_services() {
    local compose_file="$1"
    
    log "Restarting services with updated images..."
    
    cd "$PROJECT_ROOT"
    
    # Stop services gracefully
    podman-compose -f "$compose_file" stop
    
    # Start services with new images
    podman-compose -f "$compose_file" up -d
    
    # Wait for services to start
    sleep 60
    
    info "✅ Services restarted"
}

# Verify update success
verify_update() {
    log "Verifying update success..."
    
    # Check if n8n is running
    if ! podman ps | grep -q "n8n"; then
        error "n8n container is not running after update"
    fi
    
    # Perform health check
    health_check
    
    # Check new version
    local new_version
    new_version=$(get_current_version)
    info "Updated to version: $new_version"
    
    # Test basic functionality
    if podman exec n8n n8n list:workflow >/dev/null 2>&1; then
        info "✅ Basic functionality test passed"
    else
        warning "Basic functionality test failed"
        return 1
    fi
    
    return 0
}

# Rollback function
rollback() {
    local backup_dir="$1"
    
    error "Update failed, initiating rollback..."
    
    cd "$PROJECT_ROOT"
    
    # Stop current services
    podman-compose down || true
    
    # Restore from backup
    if [[ -d "$backup_dir/backup_data" ]]; then
        log "Restoring from backup..."
        
        # Restore data
        if [[ -f "$backup_dir/backup_data/n8n_data_"*.tar.gz ]]; then
            rm -rf data/n8n/*
            tar -xzf "$backup_dir/backup_data/n8n_data_"*.tar.gz -C .
        fi
        
        # Restore database if exists
        if [[ -f "$backup_dir/backup_data/database_"*.sql.gz ]] && podman ps -a | grep -q "postgres"; then
            # Start postgres
            podman start postgres || podman-compose up -d postgres
            sleep 30
            
            # Drop and recreate database
            podman exec postgres dropdb -U "${POSTGRES_USER:-n8n}" "${POSTGRES_DB:-n8n}" || true
            podman exec postgres createdb -U "${POSTGRES_USER:-n8n}" "${POSTGRES_DB:-n8n}"
            
            # Restore database
            zcat "$backup_dir/backup_data/database_"*.sql.gz | podman exec -i postgres psql -U "${POSTGRES_USER:-n8n}" "${POSTGRES_DB:-n8n}"
        fi
        
        # Restart services
        local compose_file
        if [[ -f "config/docker-compose.production.yml" ]] && [[ -f "$backup_dir/backup_data/config_"*.tar.gz ]]; then
            compose_file="config/docker-compose.production.yml"
        else
            compose_file="config/docker-compose.basic.yml"
        fi
        
        podman-compose -f "$compose_file" up -d
        
        # Wait and verify
        sleep 60
        if health_check; then
            log "✅ Rollback completed successfully"
        else
            error "Rollback failed - manual intervention required"
        fi
    else
        error "No backup found for rollback"
    fi
}

# Clean up old images
cleanup_old_images() {
    log "Cleaning up old container images..."
    
    # Remove dangling images
    podman image prune -f
    
    # Remove old n8n images (keep last 2 versions)
    podman images --format "table {{.Repository}}:{{.Tag}} {{.ID}} {{.CreatedAt}}" | \
        grep "docker.n8n.io/n8nio/n8n" | \
        tail -n +3 | \
        awk '{print $2}' | \
        xargs -r podman rmi || true
    
    info "✅ Old images cleaned up"
}

# Send update notification
send_notification() {
    local status="$1"
    local version_info="$2"
    
    if [[ -n "${NOTIFICATION_WEBHOOK:-}" ]]; then
        local message="n8n Update $status - $version_info - $(date)"
        
        curl -X POST "$NOTIFICATION_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d "{\"text\": \"$message\"}" >/dev/null 2>&1 || true
    fi
}

# Generate update report
generate_update_report() {
    local status="$1"
    local old_version="$2"
    local new_version="$3"
    
    local report_file="$PROJECT_ROOT/logs/update_report_$DATE.txt"
    
    cat > "$report_file" << EOF
n8n Update Report
=================

Date: $(date)
Status: $status
Old Version: $old_version
New Version: $new_version

Update Log: $UPDATE_LOG

System Information:
- Hostname: $(hostname)
- OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')
- Available Space: $(df -h "$PROJECT_ROOT" | tail -1 | awk '{print $4}')

Container Status After Update:
$(podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}")

Recent Updates:
$(find "$PROJECT_ROOT/logs" -name "update_report_*.txt" | sort -r | head -5 | while read -r file; do
    echo "$(basename "$file" .txt | sed 's/update_report_//'): $(grep "Status:" "$file" | cut -d: -f2 | xargs)"
done)
EOF
    
    info "Update report generated: $report_file"
}

# Main update function
main() {
    log "Starting n8n update process..."
    
    # Pre-update checks
    check_services
    
    # Check if update is needed
    if ! check_for_updates; then
        log "No updates available or version check failed"
        exit 0
    fi
    
    local current_version
    local latest_version
    current_version=$(get_current_version)
    latest_version=$(get_latest_version)
    
    # Create backup
    local backup_dir
    backup_dir=$(create_backup)
    
    # Perform update
    log "Starting update from $current_version to $latest_version..."
    
    # Update system packages
    update_system
    
    # Pull and restart with new images
    local compose_file
    compose_file=$(pull_latest_images)
    restart_services "$compose_file"
    
    # Verify update
    if verify_update; then
        log "✅ Update completed successfully!"
        
        local final_version
        final_version=$(get_current_version)
        
        # Cleanup
        cleanup_old_images
        
        # Generate reports and notifications
        generate_update_report "SUCCESS" "$current_version" "$final_version"
        send_notification "SUCCESS" "$current_version → $final_version"
        
        info "n8n updated from $current_version to $final_version"
        
        # Cleanup old update backups (keep last 5)
        find "$PROJECT_ROOT/backups/updates" -name "pre_update_*" -type d | sort -r | tail -n +6 | xargs -r rm -rf
        
    else
        # Update failed, rollback
        rollback "$backup_dir"
        generate_update_report "FAILED" "$current_version" "rollback"
        send_notification "FAILED" "Rolled back to $current_version"
        exit 1
    fi
}

# Handle script arguments
case "${1:-}" in
    --check-only)
        if check_for_updates; then
            current_version=$(get_current_version)
            latest_version=$(get_latest_version)
            echo "Update available: $current_version → $latest_version"
            exit 0
        else
            echo "No updates available"
            exit 1
        fi
        ;;
    --force)
        log "Forcing update regardless of version check..."
        # Skip version check and proceed with update
        ;;
    --help)
        echo "Usage: $0 [--check-only|--force|--help]"
        echo "  --check-only: Only check for updates, don't perform them"
        echo "  --force: Force update regardless of version check"
        echo "  --help: Show this help message"
        exit 0
        ;;
    "")
        # Default behavior - check and update if needed
        ;;
    *)
        error "Unknown option: $1. Use --help for usage information."
        ;;
esac

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi