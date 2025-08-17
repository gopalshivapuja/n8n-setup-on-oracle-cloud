#!/bin/bash

# n8n Setup Script for Oracle Cloud Free Tier
# Author: Gopal Shivapuja
# Version: 1.0
# Description: Automated setup script for n8n on Oracle Cloud

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
LOG_FILE="/tmp/n8n-setup.log"

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

# Banner
show_banner() {
    echo -e "${PURPLE}"
    cat << "EOF"
    ███╗   ██╗ █████╗ ███╗   ██╗     ███████╗███████╗████████╗██╗   ██╗██████╗ 
    ████╗  ██║██╔══██╗████╗  ██║     ██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗
    ██╔██╗ ██║╚█████╔╝██╔██╗ ██║     ███████╗█████╗     ██║   ██║   ██║██████╔╝
    ██║╚██╗██║██╔══██╗██║╚██╗██║     ╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝ 
    ██║ ╚████║╚█████╔╝██║ ╚████║     ███████║███████╗   ██║   ╚██████╔╝██║     
    ╚═╝  ╚═══╝ ╚════╝ ╚═╝  ╚═══╝     ╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝     
                                                                               
           Oracle Cloud Free Tier - Enterprise Automation for $0
EOF
    echo -e "${NC}"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        error "This script should not be run as root. Please run as a regular user with sudo privileges."
    fi
}

# Check Oracle Linux
check_os() {
    if ! grep -q "Oracle Linux" /etc/os-release; then
        warning "This script is optimized for Oracle Linux. Continuing anyway..."
    fi
}

# Check available resources
check_resources() {
    log "Checking system resources..."
    
    # Check memory
    TOTAL_MEM=$(free -g | awk '/^Mem:/ {print $2}')
    if [[ $TOTAL_MEM -lt 20 ]]; then
        warning "Less than 20GB RAM detected. Oracle Free Tier should have 24GB."
    fi
    
    # Check disk space
    AVAILABLE_SPACE=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $AVAILABLE_SPACE -lt 50 ]]; then
        warning "Less than 50GB available space. Consider cleaning up disk space."
    fi
    
    # Check CPU
    CPU_CORES=$(nproc)
    if [[ $CPU_CORES -lt 4 ]]; then
        warning "Less than 4 CPU cores detected. Oracle Free Tier should have 4 ARM cores."
    fi
    
    info "System Resources: ${TOTAL_MEM}GB RAM, ${AVAILABLE_SPACE}GB disk, ${CPU_CORES} CPU cores"
}

# Install dependencies
install_dependencies() {
    log "Installing system dependencies..."
    
    # Update system
    sudo dnf update -y
    
    # Install essential packages
    sudo dnf install -y \
        git \
        curl \
        wget \
        nano \
        htop \
        unzip \
        openssl \
        firewalld \
        python3-pip \
        container-tools \
        podman \
        podman-compose
    
    # Enable and start services
    sudo systemctl enable --now podman.socket
    sudo systemctl enable --now firewalld
    
    # Install docker-compose compatibility
    pip3 install --user podman-compose
    
    # Add to PATH
    if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
        echo 'export PATH=$PATH:~/.local/bin' >> ~/.bashrc
        export PATH=$PATH:~/.local/bin
    fi
    
    log "Dependencies installed successfully"
}

# Setup project structure
setup_project_structure() {
    log "Setting up project structure..."
    
    cd "$PROJECT_ROOT"
    
    # Create data directories
    mkdir -p data/{n8n,postgres,redis,nginx/{ssl,cache,logs,certbot}}
    mkdir -p backups/{daily,weekly,monthly}
    mkdir -p logs
    
    # Set permissions
    chmod 755 data
    chmod -R 755 backups
    chmod -R 755 logs
    
    # Create .env file if it doesn't exist
    if [[ ! -f .env ]]; then
        cp .env.example .env
        warning "Created .env file from template. Please review and update the configuration."
    fi
    
    log "Project structure created successfully"
}

# Configure firewall
configure_firewall() {
    log "Configuring firewall..."
    
    # Enable firewall
    sudo systemctl enable --now firewalld
    
    # Configure firewall rules
    sudo firewall-cmd --permanent --add-port=22/tcp    # SSH
    sudo firewall-cmd --permanent --add-port=80/tcp    # HTTP
    sudo firewall-cmd --permanent --add-port=443/tcp   # HTTPS
    sudo firewall-cmd --permanent --add-port=5678/tcp  # n8n (temporary)
    
    # Reload firewall
    sudo firewall-cmd --reload
    
    log "Firewall configured successfully"
}

# Generate secure passwords
generate_passwords() {
    log "Generating secure passwords..."
    
    # Generate random passwords
    N8N_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    
    # Update .env file
    sed -i "s/changeme_secure_password/$N8N_PASSWORD/" .env
    sed -i "s/your_secure_db_password/$POSTGRES_PASSWORD/" .env
    
    info "Generated secure passwords and updated .env file"
    info "n8n admin password: $N8N_PASSWORD"
    info "Please save these credentials securely!"
}

# Get external IP
get_external_ip() {
    log "Detecting external IP address..."
    
    EXTERNAL_IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || curl -s icanhazip.com)
    
    if [[ -n "$EXTERNAL_IP" ]]; then
        info "External IP detected: $EXTERNAL_IP"
        sed -i "s/YOUR_INSTANCE_IP/$EXTERNAL_IP/" .env
    else
        warning "Could not detect external IP. Please update .env file manually."
    fi
}

# Setup basic deployment
setup_basic() {
    log "Setting up basic n8n deployment..."
    
    # Start basic services
    podman-compose -f config/docker-compose.basic.yml up -d
    
    # Wait for services to start
    log "Waiting for services to start..."
    sleep 60
    
    # Check if n8n is running
    if podman exec n8n wget --spider -q http://localhost:5678/healthz; then
        log "✅ n8n is running successfully!"
        info "Access n8n at: http://$EXTERNAL_IP:5678"
        info "Username: admin"
        info "Password: Check your .env file"
    else
        error "❌ n8n failed to start. Check logs: podman logs n8n"
    fi
}

# Setup production deployment
setup_production() {
    log "Setting up production n8n deployment..."
    
    # Prompt for domain name
    read -p "Enter your domain name (e.g., n8n.yourdomain.com): " DOMAIN_NAME
    read -p "Enter your email for SSL certificates: " SSL_EMAIL
    
    if [[ -z "$DOMAIN_NAME" || -z "$SSL_EMAIL" ]]; then
        error "Domain name and email are required for production setup."
    fi
    
    # Update .env file
    sed -i "s/DOMAIN_NAME=.*/DOMAIN_NAME=$DOMAIN_NAME/" .env
    sed -i "s/SSL_EMAIL=.*/SSL_EMAIL=$SSL_EMAIL/" .env
    
    # Start production services
    podman-compose -f config/docker-compose.production.yml up -d postgres redis
    
    # Wait for database
    log "Waiting for database to initialize..."
    sleep 60
    
    # Start n8n
    podman-compose -f config/docker-compose.production.yml up -d n8n
    sleep 30
    
    # Generate SSL certificates
    log "Generating SSL certificates..."
    podman-compose -f config/docker-compose.production.yml --profile tools run --rm certbot \
        certonly --webroot -w /var/www/certbot -d "$DOMAIN_NAME" \
        --email "$SSL_EMAIL" --agree-tos --no-eff-email
    
    # Start nginx
    podman-compose -f config/docker-compose.production.yml up -d nginx
    
    # Remove direct n8n port access
    sudo firewall-cmd --permanent --remove-port=5678/tcp
    sudo firewall-cmd --reload
    
    log "✅ Production setup completed!"
    info "Access n8n at: https://$DOMAIN_NAME"
    info "SSL certificates are auto-renewed monthly"
}

# Setup monitoring and maintenance
setup_maintenance() {
    log "Setting up automated maintenance..."
    
    # Make scripts executable
    chmod +x scripts/maintenance/*.sh
    chmod +x scripts/security/*.sh
    chmod +x scripts/utilities/*.sh
    chmod +x scripts/recovery/*.sh
    
    # Setup cron jobs
    (crontab -l 2>/dev/null; cat << EOF
# n8n Automated Maintenance
# Daily backup at 2 AM
0 2 * * * $PROJECT_ROOT/scripts/maintenance/backup-n8n.sh >> $PROJECT_ROOT/logs/backup.log 2>&1

# Weekly update on Sundays at 3 AM
0 3 * * 0 $PROJECT_ROOT/scripts/maintenance/update-n8n.sh >> $PROJECT_ROOT/logs/update.log 2>&1

# Health check every 5 minutes
*/5 * * * * $PROJECT_ROOT/scripts/maintenance/health-check.sh >> $PROJECT_ROOT/logs/health.log 2>&1

# SSL certificate renewal (monthly)
0 1 1 * * cd $PROJECT_ROOT && podman-compose -f config/docker-compose.production.yml --profile tools run --rm certbot renew >> $PROJECT_ROOT/logs/ssl.log 2>&1

# Cleanup old logs weekly
0 4 * * 1 find $PROJECT_ROOT/logs -name "*.log" -mtime +30 -delete
EOF
    ) | crontab -
    
    log "Automated maintenance configured"
}

# Create initial backup
create_initial_backup() {
    log "Creating initial backup..."
    
    # Run backup script
    if [[ -f scripts/maintenance/backup-n8n.sh ]]; then
        chmod +x scripts/maintenance/backup-n8n.sh
        ./scripts/maintenance/backup-n8n.sh
    fi
    
    log "Initial backup created"
}

# Show final information
show_completion_info() {
    echo -e "\n${GREEN}🎉 n8n Setup Completed Successfully!${NC}\n"
    
    echo -e "${BLUE}Access Information:${NC}"
    if [[ -n "${DOMAIN_NAME:-}" ]]; then
        echo -e "  🌐 URL: https://$DOMAIN_NAME"
    else
        echo -e "  🌐 URL: http://$EXTERNAL_IP:5678"
    fi
    
    echo -e "\n${BLUE}Important Files:${NC}"
    echo -e "  📄 Configuration: $PROJECT_ROOT/.env"
    echo -e "  📁 Data Directory: $PROJECT_ROOT/data/"
    echo -e "  📁 Backups: $PROJECT_ROOT/backups/"
    echo -e "  📄 Logs: $PROJECT_ROOT/logs/"
    
    echo -e "\n${BLUE}Management Commands:${NC}"
    echo -e "  🔄 Update n8n: ./scripts/maintenance/update-n8n.sh"
    echo -e "  💾 Manual backup: ./scripts/maintenance/backup-n8n.sh"
    echo -e "  🔍 Health check: ./scripts/maintenance/health-check.sh"
    echo -e "  📊 View logs: ./scripts/utilities/view-logs.sh"
    
    echo -e "\n${BLUE}Next Steps:${NC}"
    echo -e "  1. Save your credentials securely"
    echo -e "  2. Log into n8n and complete the setup wizard"
    echo -e "  3. Create your first workflow"
    echo -e "  4. Explore the example workflows in examples/"
    
    echo -e "\n${YELLOW}Support:${NC}"
    echo -e "  📖 Documentation: https://github.com/gopalshivapuja/n8n-setup-on-oracle-cloud"
    echo -e "  🐛 Issues: https://github.com/gopalshivapuja/n8n-setup-on-oracle-cloud/issues"
    echo -e "  📝 Blog Post: https://blog.shivapuja.com/self-host-n8n-oracle-cloud"
    
    echo -e "\n${GREEN}Happy Automating! 🚀${NC}\n"
}

# Main setup function
main() {
    show_banner
    
    log "Starting n8n setup on Oracle Cloud Free Tier..."
    
    # Pre-checks
    check_root
    check_os
    check_resources
    
    # Setup
    install_dependencies
    setup_project_structure
    configure_firewall
    generate_passwords
    get_external_ip
    
    # Deployment choice
    echo -e "\n${YELLOW}Choose deployment type:${NC}"
    echo -e "  1) Basic Setup (SQLite, HTTP, quick start)"
    echo -e "  2) Production Setup (PostgreSQL, HTTPS, custom domain)"
    
    read -p "Enter your choice (1 or 2): " DEPLOYMENT_TYPE
    
    case $DEPLOYMENT_TYPE in
        1)
            setup_basic
            ;;
        2)
            setup_production
            ;;
        *)
            error "Invalid choice. Please run the script again."
            ;;
    esac
    
    # Post-setup
    setup_maintenance
    create_initial_backup
    show_completion_info
    
    log "Setup completed successfully!"
}

# Trap errors
trap 'error "Script failed at line $LINENO"' ERR

# Check if running interactively
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi