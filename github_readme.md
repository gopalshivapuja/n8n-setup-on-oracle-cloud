# n8n Self-Hosting on Oracle Cloud Free Tier

[![Oracle Cloud](https://img.shields.io/badge/Oracle_Cloud-Free_Tier-red?style=flat-square)](https://cloud.oracle.com)
[![n8n](https://img.shields.io/badge/n8n-Latest-blue?style=flat-square)](https://n8n.io)
[![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)
[![Blog Post](https://img.shields.io/badge/Blog_Post-Read_Guide-orange?style=flat-square)](https://blog.shivapuja.com/self-host-n8n-oracle-cloud)

> **Enterprise-grade workflow automation on Oracle's Always Free tier - 24GB RAM, 200GB storage, $0/month**

A complete production-ready setup for self-hosting n8n on Oracle Cloud Infrastructure's free ARM instances. This repository provides everything you need to deploy, secure, and maintain n8n with automated updates, backups, and monitoring.

## 🚀 Quick Start

```bash
# Clone this repository
git clone https://github.com/gopalshivapuja/n8n-setup-on-oracle-cloud.git
cd n8n-setup-on-oracle-cloud

# Run the automated setup
chmod +x scripts/setup.sh
./scripts/setup.sh
```

## 📋 What You Get

- ✅ **Production-ready n8n** with PostgreSQL database
- ✅ **HTTPS/SSL** with automatic Let's Encrypt certificates
- ✅ **Automated daily backups** with retention policies
- ✅ **Weekly auto-updates** for n8n and dependencies
- ✅ **Health monitoring** with automatic recovery
- ✅ **Custom domain support** with fallback options
- ✅ **Resource optimization** for Oracle's ARM architecture
- ✅ **Security hardening** with firewall and access controls

## 🏗️ Architecture

```
┌─────────────────┐    ┌──────────────┐    ┌─────────────┐
│   Internet      │────│   Nginx      │────│    n8n      │
│                 │    │   (SSL)      │    │ (Workflows) │
└─────────────────┘    └──────────────┘    └─────────────┘
                              │                    │
                       ┌──────────────┐    ┌─────────────┐
                       │  Let's       │    │ PostgreSQL  │
                       │  Encrypt     │    │ (Database)  │
                       └──────────────┘    └─────────────┘
```

## 🛠️ Prerequisites

- Oracle Cloud account (free tier)
- Domain name (optional, can use IP)
- Basic Linux command line knowledge
- 30 minutes of setup time

## 📖 Documentation

### Deployment Options

| Setup Type | Use Case | Complexity | Features |
|------------|----------|------------|----------|
| **Basic** | Testing, Learning | Low | SQLite, HTTP, IP access |
| **Production** | Real workflows | Medium | PostgreSQL, HTTPS, Domain |
| **Enterprise** | Team usage | High | Multi-user, monitoring, scaling |

### Quick Deploy Commands

#### Basic Setup (5 minutes)
```bash
./scripts/deploy-basic.sh
# Access: http://YOUR_IP:5678
```

#### Production Setup (15 minutes)
```bash
./scripts/deploy-production.sh your-domain.com your@email.com
# Access: https://n8n.your-domain.com
```

#### Enterprise Setup (30 minutes)
```bash
./scripts/deploy-enterprise.sh your-domain.com your@email.com
# Includes monitoring, scaling, team features
```

## 🔧 Configuration Files

### Core Configuration
- [`docker-compose.basic.yml`](config/docker-compose.basic.yml) - Minimal setup with SQLite
- [`docker-compose.production.yml`](config/docker-compose.production.yml) - Full production stack
- [`docker-compose.enterprise.yml`](config/docker-compose.enterprise.yml) - Multi-user with monitoring

### Nginx & SSL
- [`nginx/basic.conf`](config/nginx/basic.conf) - HTTP-only configuration
- [`nginx/ssl.conf`](config/nginx/ssl.conf) - HTTPS with Let's Encrypt
- [`nginx/advanced.conf`](config/nginx/advanced.conf) - Performance optimized

### Environment Templates
- [`.env.example`](.env.example) - Environment variables template
- [`config/n8n.env`](config/n8n.env) - n8n specific settings

## 🔐 Security Features

### Implemented Security Measures
- 🔒 **HTTPS with TLS 1.3** - End-to-end encryption
- 🛡️ **Firewall rules** - Minimal attack surface
- 🔑 **SSH key authentication** - No password access
- 🚫 **Rate limiting** - DDoS protection
- 📋 **Security headers** - XSS, CSRF protection
- 🔍 **Audit logging** - Security event tracking

### Security Checklist
```bash
# Run security audit
./scripts/security-audit.sh

# Update security settings
./scripts/harden-security.sh
```

## 📊 Monitoring & Maintenance

### Health Monitoring
```bash
# Check system health
./scripts/health-check.sh

# View resource usage
./scripts/resource-monitor.sh

# Check n8n performance
./scripts/n8n-stats.sh
```

### Automated Maintenance
- **Daily backups** at 2:00 AM UTC
- **Weekly updates** on Sundays at 3:00 AM UTC  
- **Health checks** every 5 minutes
- **SSL renewal** monthly
- **Log rotation** weekly

## 💾 Backup & Recovery

### Backup Strategy
- **Workflows**: Exported daily in JSON format
- **Database**: PostgreSQL dumps with compression
- **Configuration**: All config files and environment
- **SSL Certificates**: Let's Encrypt certificates

### Recovery Commands
```bash
# List available backups
./scripts/list-backups.sh

# Restore from specific backup
./scripts/restore-backup.sh 20240815_120000

# Emergency recovery
./scripts/emergency-restore.sh
```

## 🚀 Performance Optimization

### Oracle ARM Optimizations
- **Memory allocation**: Optimized for 24GB RAM
- **CPU scheduling**: ARM-specific optimizations  
- **Storage**: NVMe SSD optimizations
- **Network**: Bandwidth optimization

### Performance Monitoring
```bash
# Real-time performance
./scripts/performance-monitor.sh

# Generate performance report
./scripts/performance-report.sh

# Optimize configuration
./scripts/optimize-performance.sh
```

## 🔄 Update Management

### Automatic Updates
Updates are handled automatically via cron jobs:
- **n8n updates**: Weekly, with rollback capability
- **Security patches**: Daily for OS packages
- **SSL certificates**: Auto-renewal before expiry

### Manual Update Process
```bash
# Update n8n to latest version
./scripts/update-n8n.sh

# Update system packages
./scripts/update-system.sh

# Update all components
./scripts/update-all.sh
```

## 🌐 Custom Domain Setup

### DNS Configuration
1. Create A record: `n8n.yourdomain.com → YOUR_ORACLE_IP`
2. Wait for DNS propagation (5-60 minutes)
3. Run: `./scripts/configure-domain.sh n8n.yourdomain.com`

### Alternative Options
- **IP Access**: Direct IP with port 5678
- **DuckDNS**: Free dynamic DNS service
- **Oracle DNS**: Use Oracle's DNS management

## 🔍 Troubleshooting

### Common Issues

#### Connection Problems
```bash
# Check if services are running
./scripts/debug-connectivity.sh

# Verify firewall rules
./scripts/check-firewall.sh

# Test SSL configuration
./scripts/test-ssl.sh
```

#### Performance Issues
```bash
# Check resource usage
./scripts/check-resources.sh

# Analyze slow workflows
./scripts/analyze-performance.sh

# Optimize database
./scripts/optimize-database.sh
```

#### Backup/Restore Issues
```bash
# Verify backup integrity
./scripts/verify-backups.sh

# Test restore process
./scripts/test-restore.sh

# Fix backup permissions
./scripts/fix-backup-permissions.sh
```

### Debug Mode
```bash
# Enable debug logging
./scripts/enable-debug.sh

# View detailed logs
./scripts/view-logs.sh

# Disable debug mode
./scripts/disable-debug.sh
```

## 📈 Scaling Options

### Vertical Scaling (Single Instance)
- Increase Oracle instance resources
- Optimize database configuration
- Add Redis caching layer

### Horizontal Scaling (Multiple Instances)
- Load balancer setup
- Shared database configuration
- Workflow distribution strategies

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md).

### Development Setup
```bash
# Fork this repository
git clone https://github.com/YOUR_USERNAME/n8n-setup-on-oracle-cloud.git

# Create feature branch
git checkout -b feature/your-feature-name

# Make changes and test
./scripts/test-changes.sh

# Submit pull request
```

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **n8n.io** - Amazing workflow automation platform
- **Oracle Cloud** - Generous free tier offering
- **Community contributors** - Bug reports and improvements
- **Naval Ravikant** - Inspiration for building and sharing

## 📚 Additional Resources

- 📖 [Complete Setup Guide](https://blog.shivapuja.com/self-host-n8n-oracle-cloud) - Detailed blog post
- 🎥 [Video Tutorial](https://youtube.com/watch?v=your-video) - Step-by-step walkthrough
- 💬 [Community Discord](https://discord.gg/your-discord) - Get help and share experiences
- 🐛 [Issue Tracker](https://github.com/gopalshivapuja/n8n-setup-on-oracle-cloud/issues) - Report bugs

---

⭐ **Star this repository** if it helped you save money on automation tools!

**Built with ❤️ by [Gopal Shivapuja](https://github.com/gopalshivapuja)**  
*Director of Client Success @ Oracle | Automation Enthusiast*