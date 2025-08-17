# Complete Installation Guide

This guide walks you through setting up n8n on Oracle Cloud's free tier, from account creation to production deployment.

## 📋 Prerequisites

- Oracle Cloud account (free tier)
- Domain name (optional for basic setup)
- SSH client (Terminal, PuTTY, etc.)
- 30-60 minutes of setup time

## 🚀 Quick Start (Automated)

### Option 1: One-Command Setup

```bash
# Clone the repository
git clone https://github.com/gopalshivapuja/n8n-setup-on-oracle-cloud.git
cd n8n-setup-on-oracle-cloud

# Run automated setup
chmod +x scripts/setup/setup.sh
./scripts/setup/setup.sh
```

### Option 2: Production Deployment

```bash
# After cloning the repository
./scripts/setup/deploy-production.sh n8n.yourdomain.com your@email.com
```

## 📝 Manual Installation (Step by Step)

### Step 1: Oracle Cloud Account Setup

1. **Create Oracle Cloud Account**
   - Visit [cloud.oracle.com](https://cloud.oracle.com)
   - Click "Start for free"
   - Complete registration (requires phone verification and credit card for identity)
   - Wait for account approval (24-48 hours for new accounts)

2. **Access the Oracle Cloud Console**
   - Log into your Oracle Cloud account
   - Navigate to the Oracle Cloud Infrastructure (OCI) console

### Step 2: Create ARM Compute Instance

1. **Navigate to Compute Instances**
   - In the OCI console, go to **Compute** → **Instances**
   - Click **Create Instance**

2. **Configure Instance**
   ```
   Name: n8n-automation-server
   Placement: Keep default
   Image: Oracle Linux 8
   Shape: VM.Standard.A1.Flex (ARM processor)
     - OCPUs: 4 (maximum for free tier)
     - Memory: 24 GB (maximum for free tier)
   ```

3. **Configure Networking**
   ```
   Virtual Cloud Network: Default (or create new)
   Subnet: Public subnet
   Assign Public IP: Yes
   ```

4. **Add SSH Keys**
   - **Generate SSH key pair** (if you don't have one):
     ```bash
     ssh-keygen -t rsa -b 4096 -f ~/.ssh/oracle_n8n_key
     ```
   - **Upload public key**: Copy content of `~/.ssh/oracle_n8n_key.pub`
   - **⚠️ CRITICAL**: Save the private key (`~/.ssh/oracle_n8n_key`) securely

5. **Configure Boot Volume**
   ```
   Boot volume size: 200 GB (maximum for free tier)
   ```

6. **Create Instance**
   - Review configuration
   - Click **Create**
   - Wait for instance to provision (~5 minutes)
   - **Note the public IP address**

### Step 3: Configure Network Security

1. **Configure Security List**
   - Go to **Networking** → **Virtual Cloud Networks**
   - Click on your VCN → **Security Lists** → **Default Security List**
   - Click **Add Ingress Rules**

2. **Add Required Ports**
   ```
   SSH (22):
     Source: 0.0.0.0/0
     Destination Port: 22
   
   HTTP (80):
     Source: 0.0.0.0/0
     Destination Port: 80
   
   HTTPS (443):
     Source: 0.0.0.0/0
     Destination Port: 443
   
   n8n (5678) - Temporary:
     Source: 0.0.0.0/0
     Destination Port: 5678
   ```

### Step 4: Connect to Your Instance

1. **SSH Connection**
   ```bash
   ssh -i ~/.ssh/oracle_n8n_key opc@YOUR_INSTANCE_IP
   ```

2. **Update System**
   ```bash
   sudo dnf update -y
   ```

3. **Install Essential Tools**
   ```bash
   sudo dnf install -y git curl wget nano htop unzip openssl firewalld
   ```

### Step 5: Install Container Runtime

1. **Install Podman and Podman Compose**
   ```bash
   # Podman comes pre-installed on Oracle Linux 8
   podman --version
   
   # Install podman-compose
   pip3 install --user podman-compose
   
   # Add to PATH
   echo 'export PATH=$PATH:~/.local/bin' >> ~/.bashrc
   source ~/.bashrc
   ```

2. **Enable Podman Services**
   ```bash
   sudo systemctl enable --now podman.socket
   systemctl --user enable --now podman.socket
   ```

### Step 6: Clone and Setup Project

1. **Clone Repository**
   ```bash
   git clone https://github.com/gopalshivapuja/n8n-setup-on-oracle-cloud.git
   cd n8n-setup-on-oracle-cloud
   ```

2. **Create Project Structure**
   ```bash
   mkdir -p data/{n8n,postgres,redis,nginx/{ssl,cache,logs,certbot}}
   mkdir -p backups/{daily,weekly,monthly}
   mkdir -p logs
   ```

3. **Setup Environment**
   ```bash
   cp .env.example .env
   # Edit .env file with your configuration
   nano .env
   ```

### Step 7: Configure Firewall

1. **Setup Oracle Linux Firewall**
   ```bash
   sudo systemctl enable --now firewalld
   
   # Add firewall rules
   sudo firewall-cmd --permanent --add-port=22/tcp    # SSH
   sudo firewall-cmd --permanent --add-port=80/tcp    # HTTP
   sudo firewall-cmd --permanent --add-port=443/tcp   # HTTPS
   sudo firewall-cmd --permanent --add-port=5678/tcp  # n8n (temporary)
   
   # Reload firewall
   sudo firewall-cmd --reload
   ```

## 🎯 Deployment Options

### Basic Setup (Development/Testing)

Perfect for learning and testing workflows.

**Features:**
- SQLite database
- HTTP access (no SSL)
- Single container
- Quick setup (5 minutes)

**Deployment:**
```bash
# Generate secure passwords
openssl rand -base64 32 | tr -d "=+/" | cut -c1-25  # Use for N8N_BASIC_AUTH_PASSWORD

# Update .env file
nano .env

# Start n8n
podman-compose -f config/docker-compose.basic.yml up -d

# Check status
podman ps
podman logs n8n

# Access n8n
# URL: http://YOUR_IP:5678
# Username: admin
# Password: (from .env file)
```

### Production Setup (Recommended)

Enterprise-ready deployment with SSL, database, and monitoring.

**Features:**
- PostgreSQL database
- Redis caching
- HTTPS with Let's Encrypt
- Custom domain
- Automated backups
- Health monitoring

**Prerequisites:**
- Domain name pointing to your server IP
- Email address for SSL certificates

**Deployment:**
```bash
# Run production deployment script
./scripts/setup/deploy-production.sh n8n.yourdomain.com your@email.com
```

**Manual Production Setup:**
```bash
# 1. Update environment
sed -i "s/DOMAIN_NAME=.*/DOMAIN_NAME=your-domain.com/" .env
sed -i "s/SSL_EMAIL=.*/SSL_EMAIL=your@email.com/" .env

# 2. Generate secure passwords
openssl rand -base64 32 | tr -d "=+/" | cut -c1-25  # PostgreSQL password
# Update .env with generated passwords

# 3. Start database services
podman-compose -f config/docker-compose.production.yml up -d postgres redis

# 4. Wait for databases to initialize
sleep 60

# 5. Start n8n
podman-compose -f config/docker-compose.production.yml up -d n8n

# 6. Generate SSL certificates
podman-compose -f config/docker-compose.production.yml --profile tools run --rm certbot \
  certonly --webroot -w /var/www/certbot -d your-domain.com \
  --email your@email.com --agree-tos --no-eff-email

# 7. Start nginx with SSL
podman-compose -f config/docker-compose.production.yml up -d nginx

# 8. Remove direct n8n access
sudo firewall-cmd --permanent --remove-port=5678/tcp
sudo firewall-cmd --reload
```

## 🔧 Post-Installation Configuration

### 1. First Access

**Basic Setup:**
- URL: `http://YOUR_IP:5678`
- Username: `admin`
- Password: Check `.env` file

**Production Setup:**
- URL: `https://your-domain.com`
- Complete n8n setup wizard
- Create your admin account

### 2. Setup Automated Maintenance

```bash
# Make scripts executable
chmod +x scripts/maintenance/*.sh
chmod +x scripts/security/*.sh
chmod +x scripts/utilities/*.sh

# Setup cron jobs for automation
crontab -e

# Add these lines:
# Daily backup at 2 AM
0 2 * * * /home/opc/n8n-setup-on-oracle-cloud/scripts/maintenance/backup-n8n.sh

# Weekly update on Sundays at 3 AM  
0 3 * * 0 /home/opc/n8n-setup-on-oracle-cloud/scripts/maintenance/update-n8n.sh

# Health check every 5 minutes
*/5 * * * * /home/opc/n8n-setup-on-oracle-cloud/scripts/maintenance/health-check.sh

# SSL renewal (monthly)
0 1 1 * * cd /home/opc/n8n-setup-on-oracle-cloud && podman-compose -f config/docker-compose.production.yml --profile tools run --rm certbot renew
```

### 3. Security Hardening

```bash
# Run security audit
./scripts/security/security-audit.sh

# Apply security hardening
./scripts/security/harden-security.sh

# Configure additional firewall rules
./scripts/security/configure-firewall.sh
```

## 🔍 Verification and Testing

### Health Checks

```bash
# Check service status
podman ps

# Check n8n health
curl http://localhost:5678/healthz

# Check logs
podman logs n8n
podman logs postgres  # (production only)
podman logs nginx     # (production only)
```

### Test Functionality

1. **Access n8n interface**
2. **Create a simple workflow**
3. **Test webhook functionality**
4. **Verify email notifications** (if configured)

### Performance Testing

```bash
# Check resource usage
./scripts/utilities/resource-monitor.sh

# Generate performance report
./scripts/utilities/performance-report.sh

# Test backup and restore
./scripts/maintenance/backup-n8n.sh
./scripts/recovery/verify-backups.sh
```

## 🚨 Troubleshooting

### Common Issues

#### 1. SSH Connection Failed
```bash
# Check if IP is correct
ping YOUR_INSTANCE_IP

# Verify SSH key permissions
chmod 600 ~/.ssh/oracle_n8n_key

# Try verbose SSH
ssh -v -i ~/.ssh/oracle_n8n_key opc@YOUR_INSTANCE_IP
```

#### 2. n8n Won't Start
```bash
# Check logs
podman logs n8n

# Check if port is available
ss -tlnp | grep 5678

# Restart services
podman-compose restart
```

#### 3. SSL Certificate Issues
```bash
# Check DNS resolution
dig your-domain.com A

# Verify nginx configuration
podman exec nginx nginx -t

# Check certificate status
echo | openssl s_client -servername your-domain.com -connect your-domain.com:443
```

#### 4. Database Connection Issues
```bash
# Check PostgreSQL status
podman exec postgres pg_isready

# Test database connection
podman exec postgres psql -U n8n -d n8n -c "SELECT version();"

# Check environment variables
podman exec n8n env | grep DB_
```

### Getting Help

1. **Check logs first**:
   ```bash
   ./scripts/utilities/view-logs.sh
   ```

2. **Run diagnostics**:
   ```bash
   ./scripts/utilities/debug-connectivity.sh
   ```

3. **Create an issue** on GitHub with:
   - Your setup type (basic/production)
   - Error messages
   - Relevant log excerpts
   - System information

## 📚 Next Steps

1. **Explore Example Workflows**: Check `examples/workflows/` directory
2. **Configure Integrations**: See `examples/integrations/` for setup guides
3. **Setup Monitoring**: Enable advanced monitoring with Grafana
4. **Scale Your Setup**: Consider multi-instance deployment for high availability

## 🔗 Additional Resources

- [n8n Documentation](https://docs.n8n.io/)
- [Oracle Cloud Documentation](https://docs.oracle.com/en-us/iaas/)
- [Blog Post](https://blog.shivapuja.com/self-host-n8n-oracle-cloud)
- [GitHub Issues](https://github.com/gopalshivapuja/n8n-setup-on-oracle-cloud/issues)