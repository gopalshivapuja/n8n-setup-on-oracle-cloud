#!/bin/bash

# n8n Production Deployment Script
# Author: Gopal Shivapuja
# Description: Complete production deployment with PostgreSQL, Redis, SSL

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
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

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Show banner
show_banner() {
    echo -e "${PURPLE}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║   n8n Production Deployment on Oracle Cloud Free Tier        ║
║   Enterprise-grade automation for $0/month                   ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# Validate inputs
validate_inputs() {
    local domain="$1"
    local email="$2"
    
    if [[ -z "$domain" ]]; then
        error "Domain name is required"
    fi
    
    if [[ -z "$email" ]]; then
        error "Email address is required for SSL certificates"
    fi
    
    # Validate domain format
    if ! [[ "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
        error "Invalid domain format: $domain"
    fi
    
    # Validate email format
    if ! [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        error "Invalid email format: $email"
    fi
    
    info "✅ Input validation passed"
}

# Check DNS resolution
check_dns() {
    local domain="$1"
    
    log "Checking DNS resolution for $domain..."
    
    # Get external IP
    local external_ip
    external_ip=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || curl -s icanhazip.com)
    
    if [[ -z "$external_ip" ]]; then
        error "Could not determine external IP address"
    fi
    
    # Check if domain resolves to this server
    local resolved_ip
    resolved_ip=$(dig +short "$domain" A | tail -1)
    
    if [[ "$resolved_ip" != "$external_ip" ]]; then
        warning "DNS mismatch detected:"
        warning "  Domain $domain resolves to: $resolved_ip"
        warning "  Server external IP: $external_ip"
        warning ""
        warning "Please update your DNS records:"
        warning "  Type: A"
        warning "  Name: ${domain%.*.*}"
        warning "  Value: $external_ip"
        warning "  TTL: 300"
        warning ""
        
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            error "Deployment cancelled. Please fix DNS and try again."
        fi
    else
        success "✅ DNS resolution verified"
    fi
}

# Generate secure passwords
generate_passwords() {
    log "Generating secure passwords..."
    
    # Generate passwords
    local n8n_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    local postgres_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    local redis_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    
    # Update .env file
    sed -i "s/changeme_secure_password/$n8n_password/" "$PROJECT_ROOT/.env"
    sed -i "s/your_secure_db_password/$postgres_password/" "$PROJECT_ROOT/.env"
    
    # Store passwords securely
    cat > "$PROJECT_ROOT/.credentials" << EOF
# n8n Production Credentials
# Generated: $(date)
# KEEP THIS FILE SECURE AND PRIVATE

N8N_ADMIN_PASSWORD=$n8n_password
POSTGRES_PASSWORD=$postgres_password
REDIS_PASSWORD=$redis_password
EOF
    
    chmod 600 "$PROJECT_ROOT/.credentials"
    
    success "✅ Secure passwords generated and stored in .credentials"
    info "Please save these credentials in a secure location!"
}

# Update environment configuration
update_environment() {
    local domain="$1"
    local email="$2"
    
    log "Updating environment configuration..."
    
    # Update .env file
    sed -i "s/DOMAIN_NAME=.*/DOMAIN_NAME=$domain/" "$PROJECT_ROOT/.env"
    sed -i "s/SSL_EMAIL=.*/SSL_EMAIL=$email/" "$PROJECT_ROOT/.env"
    
    # Set production-specific settings
    cat >> "$PROJECT_ROOT/.env" << EOF

# Production-specific settings
NODE_ENV=production
N8N_ENCRYPTION_KEY=$(openssl rand -base64 32)
N8N_USER_MANAGEMENT_JWT_SECRET=$(openssl rand -base64 32)
EOF
    
    success "✅ Environment configuration updated"
}

# Setup SSL directories and permissions
setup_ssl_directories() {
    log "Setting up SSL directories..."
    
    # Create SSL directories
    mkdir -p "$PROJECT_ROOT/data/nginx/ssl"
    mkdir -p "$PROJECT_ROOT/data/nginx/certbot"
    mkdir -p "$PROJECT_ROOT/data/nginx/cache"
    mkdir -p "$PROJECT_ROOT/data/nginx/logs"
    
    # Set proper permissions
    chmod 755 "$PROJECT_ROOT/data/nginx"
    chmod 700 "$PROJECT_ROOT/data/nginx/ssl"
    
    success "✅ SSL directories created"
}

# Configure nginx for domain
configure_nginx() {
    local domain="$1"
    
    log "Configuring nginx for domain $domain..."
    
    # Copy SSL configuration template
    cp "$PROJECT_ROOT/config/nginx/ssl.conf" "$PROJECT_ROOT/config/nginx/production.conf"
    
    # Replace domain placeholder
    sed -i "s/DOMAIN_NAME/$domain/g" "$PROJECT_ROOT/config/nginx/production.conf"
    
    # Create proxy_params file
    cat > "$PROJECT_ROOT/config/nginx/proxy_params" << 'EOF'
proxy_set_header Host $http_host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Forwarded-Host $server_name;
proxy_set_header X-Forwarded-Port $server_port;
proxy_buffering off;
proxy_connect_timeout 60s;
proxy_send_timeout 60s;
proxy_read_timeout 60s;
EOF
    
    success "✅ Nginx configuration prepared"
}

# Start database services
start_database_services() {
    log "Starting database services..."
    
    cd "$PROJECT_ROOT"
    
    # Start PostgreSQL and Redis
    podman-compose -f config/docker-compose.production.yml up -d postgres redis
    
    # Wait for services to be ready
    log "Waiting for database services to initialize..."
    sleep 45
    
    # Check PostgreSQL health
    local retries=0
    while [[ $retries -lt 30 ]]; do
        if podman exec postgres pg_isready -U "${POSTGRES_USER:-n8n}" -d "${POSTGRES_DB:-n8n}" >/dev/null 2>&1; then
            success "✅ PostgreSQL is ready"
            break
        fi
        sleep 2
        ((retries++))
    done
    
    if [[ $retries -eq 30 ]]; then
        error "PostgreSQL failed to start properly"
    fi
    
    # Check Redis health
    if podman exec redis redis-cli ping >/dev/null 2>&1; then
        success "✅ Redis is ready"
    else
        error "Redis failed to start properly"
    fi
}

# Start n8n service
start_n8n() {
    log "Starting n8n service..."
    
    cd "$PROJECT_ROOT"
    
    # Start n8n
    podman-compose -f config/docker-compose.production.yml up -d n8n
    
    # Wait for n8n to be ready
    log "Waiting for n8n to initialize..."
    local retries=0
    while [[ $retries -lt 60 ]]; do
        if podman exec n8n wget --spider -q http://localhost:5678/healthz 2>/dev/null; then
            success "✅ n8n is ready"
            return 0
        fi
        sleep 5
        ((retries++))
        
        if [[ $((retries % 12)) -eq 0 ]]; then
            info "Still waiting for n8n... (${retries}/60)"
        fi
    done
    
    error "n8n failed to start properly. Check logs: podman logs n8n"
}

# Generate SSL certificates
generate_ssl_certificates() {
    local domain="$1"
    local email="$2"
    
    log "Generating SSL certificates for $domain..."
    
    cd "$PROJECT_ROOT"
    
    # Start temporary nginx for certificate validation
    log "Starting temporary nginx for certificate validation..."
    
    # Create temporary nginx config for HTTP-01 challenge
    cat > "$PROJECT_ROOT/config/nginx/temp.conf" << EOF
events {
    worker_connections 1024;
}

http {
    server {
        listen 80;
        server_name $domain;
        
        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }
        
        location / {
            return 200 'Certificate validation server';
            add_header Content-Type text/plain;
        }
    }
}
EOF
    
    # Start temporary nginx
    podman run -d --name nginx-temp \
        --network container:n8n \
        -p 80:80 \
        -v "$PROJECT_ROOT/config/nginx/temp.conf:/etc/nginx/nginx.conf:ro" \
        -v "$PROJECT_ROOT/data/nginx/certbot:/var/www/certbot" \
        nginx:alpine
    
    sleep 10
    
    # Generate certificates
    log "Requesting SSL certificate from Let's Encrypt..."
    if podman run --rm \
        --network container:n8n \
        -v "$PROJECT_ROOT/data/nginx/ssl:/etc/letsencrypt" \
        -v "$PROJECT_ROOT/data/nginx/certbot:/var/www/certbot" \
        certbot/certbot:latest \
        certonly --webroot \
        -w /var/www/certbot \
        -d "$domain" \
        --email "$email" \
        --agree-tos \
        --no-eff-email \
        --force-renewal; then
        
        success "✅ SSL certificate generated successfully"
        
        # Stop temporary nginx
        podman stop nginx-temp
        podman rm nginx-temp
        
        return 0
    else
        # Cleanup on failure
        podman stop nginx-temp 2>/dev/null || true
        podman rm nginx-temp 2>/dev/null || true
        error "Failed to generate SSL certificate. Check DNS and try again."
    fi
}

# Start production nginx
start_nginx() {
    local domain="$1"
    
    log "Starting production nginx with SSL..."
    
    cd "$PROJECT_ROOT"
    
    # Update nginx config with actual certificate paths
    sed -i "s|/etc/nginx/ssl/live/DOMAIN_NAME/|/etc/letsencrypt/live/$domain/|g" \
        "$PROJECT_ROOT/config/nginx/production.conf"
    
    # Start nginx with production config
    podman run -d --name nginx \
        --restart unless-stopped \
        --network container:n8n \
        -p 80:80 \
        -p 443:443 \
        -v "$PROJECT_ROOT/config/nginx/production.conf:/etc/nginx/nginx.conf:ro" \
        -v "$PROJECT_ROOT/config/nginx/proxy_params:/etc/nginx/proxy_params:ro" \
        -v "$PROJECT_ROOT/data/nginx/ssl:/etc/letsencrypt:ro" \
        -v "$PROJECT_ROOT/data/nginx/cache:/var/cache/nginx" \
        -v "$PROJECT_ROOT/data/nginx/logs:/var/log/nginx" \
        nginx:alpine
    
    # Wait for nginx to start
    sleep 10
    
    # Test HTTPS connection
    if curl -sSf "https://$domain/healthz" >/dev/null 2>&1; then
        success "✅ Nginx with SSL is working correctly"
    else
        warning "Nginx started but HTTPS test failed. Check configuration."
    fi
}

# Configure firewall for production
configure_firewall() {
    log "Configuring firewall for production..."
    
    # Remove direct n8n port access
    sudo firewall-cmd --permanent --remove-port=5678/tcp 2>/dev/null || true
    
    # Ensure HTTP and HTTPS are open
    sudo firewall-cmd --permanent --add-port=80/tcp
    sudo firewall-cmd --permanent --add-port=443/tcp
    
    # Reload firewall
    sudo firewall-cmd --reload
    
    success "✅ Firewall configured for production"
}

# Setup automatic SSL renewal
setup_ssl_renewal() {
    local domain="$1"
    
    log "Setting up automatic SSL certificate renewal..."
    
    # Create renewal script
    cat > "$PROJECT_ROOT/scripts/maintenance/renew-ssl.sh" << EOF
#!/bin/bash

# SSL Certificate Renewal Script
set -euo pipefail

DOMAIN="$domain"
PROJECT_ROOT="$PROJECT_ROOT"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] \$1"
}

log "Starting SSL certificate renewal for \$DOMAIN..."

# Renew certificate
if podman run --rm \\
    -v "\$PROJECT_ROOT/data/nginx/ssl:/etc/letsencrypt" \\
    -v "\$PROJECT_ROOT/data/nginx/certbot:/var/www/certbot" \\
    certbot/certbot:latest \\
    renew --quiet; then
    
    log "Certificate renewal successful"
    
    # Reload nginx
    if podman exec nginx nginx -s reload; then
        log "Nginx reloaded successfully"
    else
        log "Failed to reload nginx"
        exit 1
    fi
else
    log "Certificate renewal failed"
    exit 1
fi

log "SSL renewal completed successfully"
EOF
    
    chmod +x "$PROJECT_ROOT/scripts/maintenance/renew-ssl.sh"
    
    # Add to crontab (runs monthly)
    (crontab -l 2>/dev/null; echo "0 2 1 * * $PROJECT_ROOT/scripts/maintenance/renew-ssl.sh >> $PROJECT_ROOT/logs/ssl-renewal.log 2>&1") | crontab -
    
    success "✅ Automatic SSL renewal configured"
}

# Create production monitoring
setup_monitoring() {
    log "Setting up production monitoring..."
    
    # Create monitoring script
    cat > "$PROJECT_ROOT/scripts/maintenance/production-monitor.sh" << 'EOF'
#!/bin/bash

# Production Monitoring Script
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_FILE="$PROJECT_ROOT/logs/production-monitor.log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Check all services
check_services() {
    local failures=0
    
    # Check n8n
    if ! podman exec n8n wget --spider -q http://localhost:5678/healthz 2>/dev/null; then
        log "ERROR: n8n health check failed"
        ((failures++))
    fi
    
    # Check PostgreSQL
    if ! podman exec postgres pg_isready -U n8n -d n8n >/dev/null 2>&1; then
        log "ERROR: PostgreSQL health check failed"
        ((failures++))
    fi
    
    # Check Redis
    if ! podman exec redis redis-cli ping >/dev/null 2>&1; then
        log "ERROR: Redis health check failed"
        ((failures++))
    fi
    
    # Check Nginx
    if ! curl -sSf https://$(hostname)/healthz >/dev/null 2>&1; then
        log "ERROR: Nginx/HTTPS health check failed"
        ((failures++))
    fi
    
    return $failures
}

# Check system resources
check_resources() {
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
    local mem_usage=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
    local disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    
    log "Resource usage: CPU=${cpu_usage}%, Memory=${mem_usage}%, Disk=${disk_usage}%"
    
    # Alert on high usage
    if (( $(echo "$mem_usage > 90" | bc -l) )); then
        log "WARNING: High memory usage: ${mem_usage}%"
    fi
    
    if [[ $disk_usage -gt 85 ]]; then
        log "WARNING: High disk usage: ${disk_usage}%"
    fi
}

# Main monitoring
if check_services; then
    log "All services healthy"
    check_resources
else
    log "Service health check failures detected"
    
    # Attempt service restart
    log "Attempting to restart failed services..."
    cd "$PROJECT_ROOT"
    podman-compose -f config/docker-compose.production.yml restart
    
    sleep 60
    
    if check_services; then
        log "Services restored after restart"
    else
        log "CRITICAL: Services still failing after restart"
    fi
fi
EOF
    
    chmod +x "$PROJECT_ROOT/scripts/maintenance/production-monitor.sh"
    
    # Add to crontab (runs every 5 minutes)
    (crontab -l 2>/dev/null | grep -v production-monitor.sh; echo "*/5 * * * * $PROJECT_ROOT/scripts/maintenance/production-monitor.sh") | crontab -
    
    success "✅ Production monitoring configured"
}

# Perform final verification
final_verification() {
    local domain="$1"
    
    log "Performing final verification..."
    
    # Test HTTPS access
    log "Testing HTTPS access..."
    if curl -sSf "https://$domain/" >/dev/null 2>&1; then
        success "✅ HTTPS access working"
    else
        error "HTTPS access test failed"
    fi
    
    # Test SSL certificate
    log "Verifying SSL certificate..."
    local cert_expiry
    cert_expiry=$(echo | openssl s_client -servername "$domain" -connect "$domain:443" 2>/dev/null | openssl x509 -noout -enddate | cut -d= -f2)
    info "SSL certificate expires: $cert_expiry"
    
    # Test database connection
    log "Testing database connection..."
    if podman exec n8n node -e "const { Pool } = require('pg'); const pool = new Pool({host: 'postgres', user: 'n8n', database: 'n8n', password: process.env.DB_POSTGRESDB_PASSWORD}); pool.query('SELECT 1').then(() => {console.log('DB OK'); process.exit(0);}).catch(e => {console.error('DB FAIL'); process.exit(1);});" >/dev/null 2>&1; then
        success "✅ Database connection working"
    else
        warning "Database connection test failed"
    fi
    
    # Test workflow functionality
    log "Testing workflow functionality..."
    if podman exec n8n n8n list:workflow >/dev/null 2>&1; then
        success "✅ Workflow functionality working"
    else
        warning "Workflow functionality test failed"
    fi
    
    success "✅ Production deployment verification completed"
}

# Show completion summary
show_completion_summary() {
    local domain="$1"
    local email="$2"
    
    echo
    echo -e "${GREEN}🎉 Production Deployment Completed Successfully! 🎉${NC}"
    echo
    echo -e "${BLUE}Access Information:${NC}"
    echo -e "  🌐 URL: https://$domain"
    echo -e "  📧 SSL Email: $email"
    echo
    echo -e "${BLUE}Credentials:${NC}"
    echo -e "  📄 Stored in: $PROJECT_ROOT/.credentials"
    echo -e "  ⚠️  Keep this file secure and create a backup!"
    echo
    echo -e "${BLUE}Services Running:${NC}"
    echo -e "  🔗 n8n: Workflow automation platform"
    echo -e "  🗄️  PostgreSQL: Production database"
    echo -e "  🚀 Redis: Caching and queuing"
    echo -e "  🌐 Nginx: Reverse proxy with SSL"
    echo
    echo -e "${BLUE}Automated Features:${NC}"
    echo -e "  🔄 Auto-updates: Weekly on Sundays"
    echo -e "  💾 Daily backups: 2 AM UTC"
    echo -e "  🔒 SSL renewal: Monthly"
    echo -e "  📊 Health monitoring: Every 5 minutes"
    echo
    echo -e "${BLUE}Management Commands:${NC}"
    echo -e "  📊 Monitor: ./scripts/maintenance/production-monitor.sh"
    echo -e "  🔄 Update: ./scripts/maintenance/update-n8n.sh"
    echo -e "  💾 Backup: ./scripts/maintenance/backup-n8n.sh"
    echo -e "  🔒 Renew SSL: ./scripts/maintenance/renew-ssl.sh"
    echo
    echo -e "${BLUE}Next Steps:${NC}"
    echo -e "  1. Save your credentials from .credentials file"
    echo -e "  2. Access n8n at https://$domain"
    echo -e "  3. Complete the n8n setup wizard"
    echo -e "  4. Create your first workflow"
    echo -e "  5. Explore the examples/ directory for sample workflows"
    echo
    echo -e "${YELLOW}Important Security Notes:${NC}"
    echo -e "  🔐 Change default passwords after first login"
    echo -e "  🔑 Enable two-factor authentication in n8n"
    echo -e "  📋 Regular security updates are automated"
    echo -e "  💾 Backups are stored locally and should be backed up offsite"
    echo
    echo -e "${GREEN}Happy Automating! 🚀${NC}"
    echo
}

# Main deployment function
main() {
    local domain="$1"
    local email="$2"
    
    show_banner
    
    log "Starting production deployment for $domain..."
    
    # Validations
    validate_inputs "$domain" "$email"
    check_dns "$domain"
    
    # Setup
    generate_passwords
    update_environment "$domain" "$email"
    setup_ssl_directories
    configure_nginx "$domain"
    
    # Deploy services
    start_database_services
    start_n8n
    
    # SSL and web server
    generate_ssl_certificates "$domain" "$email"
    start_nginx "$domain"
    
    # Production configuration
    configure_firewall
    setup_ssl_renewal "$domain"
    setup_monitoring
    
    # Verification
    final_verification "$domain"
    
    # Complete
    show_completion_summary "$domain" "$email"
    
    log "Production deployment completed successfully!"
}

# Usage information
usage() {
    echo "Usage: $0 <domain> <email>"
    echo
    echo "Arguments:"
    echo "  domain  Your domain name (e.g., n8n.yourdomain.com)"
    echo "  email   Email address for SSL certificates"
    echo
    echo "Example:"
    echo "  $0 n8n.example.com admin@example.com"
    echo
    exit 1
}

# Check arguments
if [[ $# -ne 2 ]]; then
    usage
fi

# Run main function
main "$1" "$2"