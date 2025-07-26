# Complete Hetzner Cloud Deployment Guide

## Prerequisites Completed ✅
- Hetzner Cloud account created
- SSH key generated (`~/.ssh/hetzner_key`)
- SSH key added via CLI (avoiding web interface bug)
- Hetzner CLI installed (`brew install hcloud`)
- API token created with Read & Write permissions

## Step 1: Create Server via CLI

```bash
# Make the script executable
chmod +x hetzner-cli-setup.sh

# Set your API token (if not already set)
export HCLOUD_TOKEN="your-api-token-here"

# Run the server creation script
./hetzner-cli-setup.sh
```

This script will:
- Create a CPX11 server (2 vCPU, 2GB RAM) for €4.15/month
- Configure firewall rules
- Set up basic security (UFW, fail2ban)
- Save server details to `server-info.json`
- Optionally help with DNS setup (DuckDNS or Cloudflare)

## Step 2: DNS Setup Options

### Option A: DuckDNS (Free, Instant)
1. Go to https://www.duckdns.org
2. Sign in with GitHub/Reddit/Twitter
3. Create subdomain (e.g., `yourname-passkey`)
4. The script can configure auto-update

### Option B: Cloudflare (Recommended for Production)
1. Add A record pointing to server IP
2. Enable proxy (orange cloud) for DDoS protection
3. Set up rate limiting rules

### Option C: Your Own Domain
- Point A record to server IP
- Wait for DNS propagation (5-30 minutes)

## Step 3: Deploy Passkey Server

```bash
# Make deployment script executable
chmod +x deploy-passkey-server.sh

# Run deployment
./deploy-passkey-server.sh
```

The script will ask for:
- Your domain (e.g., `passkey.yourdomain.com`)
- Email for SSL certificates
- Then automatically generates secure passwords

## What Gets Deployed

### Security Features
- ✅ Node.js 20 (required version)
- ✅ PostgreSQL with encrypted passwords
- ✅ Nginx with rate limiting
- ✅ SSL certificate (Let's Encrypt)
- ✅ PM2 process manager
- ✅ Fail2ban intrusion prevention
- ✅ Automated daily backups
- ✅ Health monitoring with auto-restart
- ✅ Security headers
- ✅ Firewall configured

### Your Actual Server
- ✅ Full PostgreSQL integration
- ✅ Encrypted data storage endpoints
- ✅ User management
- ✅ Dashboard
- ✅ All features from your local `index.js`

## Post-Deployment Steps

### 1. Create Non-Root User (Important!)
```bash
ssh -i ~/.ssh/hetzner_key root@SERVER_IP

# Create new user
adduser yourusername
usermod -aG sudo yourusername

# Copy SSH key
mkdir -p /home/yourusername/.ssh
cp ~/.ssh/authorized_keys /home/yourusername/.ssh/
chown -R yourusername:yourusername /home/yourusername/.ssh

# Test login with new user
exit
ssh -i ~/.ssh/hetzner_key yourusername@SERVER_IP
```

### 2. Update iOS App
In your Swift app, update the base URL:
```swift
private var baseURL: String {
    return "https://your-domain.com"  // Your actual domain
}
```

### 3. Test All Endpoints
```bash
# Health check
curl https://your-domain.com/health

# Registration options
curl https://your-domain.com/generate-registration-options

# Dashboard
open https://your-domain.com/dashboard
```

### 4. Monitor Your Server
```bash
# View logs
ssh yourusername@SERVER_IP "pm2 logs passkey-server"

# Check status
ssh yourusername@SERVER_IP "pm2 status"

# View Nginx access logs
ssh yourusername@SERVER_IP "sudo tail -f /var/log/nginx/access.log"
```

## File Structure After Deployment

```
/var/www/passkey-server/
├── index.js          # Your actual passkey server
├── db.js             # Database module
├── package.json      # Dependencies
├── .env              # Environment variables (secure)
├── ecosystem.config.js # PM2 configuration
└── node_modules/     # Installed packages

/home/passkey/
├── backup.sh         # Automated backup script
├── health-check.sh   # Health monitoring
└── backups/          # Backup directory
```

## Security Checklist

- [x] SSH key authentication only
- [x] Firewall configured (UFW)
- [x] Fail2ban active
- [x] SSL certificate installed
- [x] Rate limiting configured
- [x] Security headers set
- [x] Automated backups
- [x] Database passwords encrypted
- [ ] Root SSH disabled (after creating user)
- [ ] Regular security updates scheduled

## Maintenance Commands

```bash
# Update server packages
sudo apt update && sudo apt upgrade

# Restart passkey server
pm2 restart passkey-server

# View error logs
pm2 logs passkey-server --err

# Backup database manually
sudo -u postgres pg_dump passkey_db > backup.sql

# Check SSL certificate
sudo certbot certificates

# Monitor server resources
htop
```

## Troubleshooting

### Server won't start
```bash
# Check logs
pm2 logs passkey-server

# Check if port 3000 is in use
sudo lsof -i :3000

# Restart everything
pm2 stop all
pm2 start ecosystem.config.js
```

### SSL issues
```bash
# Renew certificate manually
sudo certbot renew --force-renewal

# Check Nginx config
sudo nginx -t
```

### Database connection issues
```bash
# Check PostgreSQL status
sudo systemctl status postgresql

# View PostgreSQL logs
sudo tail -f /var/log/postgresql/*.log
```

## Cost Summary

- **Server**: €4.15/month (CPX11)
- **Backups**: €0.83/month (recommended)
- **Total**: ~€5/month

## Support Resources

- **Hetzner Status**: https://status.hetzner.com
- **Hetzner Docs**: https://docs.hetzner.com
- **PM2 Docs**: https://pm2.keymetrics.io
- **Let's Encrypt**: https://letsencrypt.org/docs

## 🎉 Congratulations!

Your passkey server is now live, secure, and ready for production use. The server will:
- Auto-restart on crashes
- Auto-renew SSL certificates
- Auto-backup daily
- Auto-monitor health

Remember to:
1. Save all generated passwords
2. Set up monitoring (UptimeRobot)
3. Review logs weekly
4. Keep the server updated