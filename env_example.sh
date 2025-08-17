# n8n Oracle Cloud Configuration
# Copy this file to .env and update the values

# =============================================================================
# BASIC CONFIGURATION
# =============================================================================

# External IP (detected automatically by setup script)
EXTERNAL_IP=YOUR_INSTANCE_IP

# Timezone (Oracle Cloud default is UTC)
TIMEZONE=UTC

# =============================================================================
# AUTHENTICATION
# =============================================================================

# n8n Basic Auth (used for basic setup)
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=changeme_secure_password

# =============================================================================
# DOMAIN AND SSL
# =============================================================================

# Your custom domain (for production setup)
DOMAIN_NAME=n8n.yourdomain.com

# Email for Let's Encrypt SSL certificates
SSL_EMAIL=your@email.com

# =============================================================================
# DATABASE CONFIGURATION
# =============================================================================

# PostgreSQL settings (for production setup)
POSTGRES_DB=n8n
POSTGRES_USER=n8n
POSTGRES_PASSWORD=your_secure_db_password

# =============================================================================
# PERFORMANCE TUNING
# =============================================================================

# n8n Performance Settings
N8N_PAYLOAD_SIZE_MAX=128
EXECUTIONS_TIMEOUT=3600
EXECUTIONS_TIMEOUT_MAX=7200

# Database connections
DB_POSTGRESDB_POOL_SIZE=10

# =============================================================================
# BACKUP CONFIGURATION
# =============================================================================

# Backup retention (days)
BACKUP_RETENTION_DAYS=30

# Backup storage location
BACKUP_PATH=/home/opc/n8n-setup/backups

# =============================================================================
# MONITORING AND LOGGING
# =============================================================================

# Log level (error, warn, info, verbose, debug, silly)
N8N_LOG_LEVEL=info

# Enable metrics endpoint
N8N_METRICS=true

# =============================================================================
# SECURITY SETTINGS
# =============================================================================

# Security headers
NGINX_SECURITY_HEADERS=true

# Rate limiting
NGINX_RATE_LIMIT=true

# =============================================================================
# ADVANCED SETTINGS
# =============================================================================

# n8n workflow execution
EXECUTIONS_PROCESS=main
EXECUTIONS_MODE=regular

# Data pruning
EXECUTIONS_DATA_PRUNE=true
EXECUTIONS_DATA_MAX_AGE=168

# Binary data
N8N_BINARY_DATA_MODE=filesystem
N8N_BINARY_DATA_TTL=24

# =============================================================================
# ORACLE CLOUD SPECIFIC
# =============================================================================

# Oracle Cloud tenancy (for object storage backups - optional)
# OCI_TENANCY_ID=your_tenancy_id
# OCI_USER_ID=your_user_id
# OCI_FINGERPRINT=your_key_fingerprint
# OCI_PRIVATE_KEY_PATH=/path/to/private/key

# Object storage bucket for backups (optional)
# OCI_BUCKET_NAME=n8n-backups
# OCI_REGION=us-ashburn-1

# =============================================================================
# DEVELOPMENT SETTINGS (uncomment if needed)
# =============================================================================

# Enable debug mode
# N8N_LOG_LEVEL=debug
# NODE_ENV=development

# Disable authentication for development (NOT for production)
# N8N_BASIC_AUTH_ACTIVE=false

# Allow embedding (for iframe usage)
# N8N_DISABLE_UI=false