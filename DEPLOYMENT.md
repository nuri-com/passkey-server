# Deployment Guide

This guide explains how to deploy the passkey server to production.

## Prerequisites

- A domain name with DNS control
- A server (we use Hetzner Cloud CPX11 - €4.15/month)
- SSL certificate (automated with Let's Encrypt)

## Architecture Overview

```
iOS App (webcredentials:yourdomain.com)
    ↓
passkey.yourdomain.com (Server URL)
    ↓
RP_ID: yourdomain.com (Parent domain for iOS compatibility)
```

## Server Requirements

- **OS**: Ubuntu 22.04 LTS
- **Node.js**: 20.x (required)
- **PostgreSQL**: 14+
- **RAM**: 2GB minimum
- **CPU**: 2 vCPU recommended

## Deployment Steps

### 1. Server Setup

1. Create a new Ubuntu 22.04 server
2. Point your DNS A record to the server IP
   - Example: `passkey.yourdomain.com → SERVER_IP`
3. SSH into the server

### 2. Install Dependencies

```bash
# Update system
apt update && apt upgrade -y

# Install Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

# Install PostgreSQL
apt install -y postgresql postgresql-contrib

# Install Nginx and Certbot
apt install -y nginx certbot python3-certbot-nginx

# Install PM2 for process management
npm install -g pm2
```

### 3. Database Setup

```bash
# Create database and user
sudo -u postgres psql
CREATE DATABASE passkey_db;
CREATE USER passkey_user WITH ENCRYPTED PASSWORD 'your-secure-password';
GRANT ALL PRIVILEGES ON DATABASE passkey_db TO passkey_user;
\q
```

### 4. Application Setup

```bash
# Create app directory
mkdir -p /var/www/passkey-server
cd /var/www/passkey-server

# Copy your application files here
# Install dependencies
npm install --production

# Create .env file (see .env.example)
```

### 5. Environment Configuration

Create `.env` file with:

```env
# Database
DATABASE_URL=postgresql://passkey_user:password@localhost:5432/passkey_db

# Server
PORT=3000
NODE_ENV=production

# WebAuthn Configuration (IMPORTANT)
RP_ID=yourdomain.com          # Parent domain (not subdomain!)
RP_NAME=Your App Name
ORIGIN=https://passkey.yourdomain.com

# Security
SESSION_SECRET=<generate-random-secret>
```

**Critical**: For iOS compatibility, `RP_ID` must be the parent domain, not the subdomain!

### 6. Nginx Configuration

```nginx
server {
    server_name passkey.yourdomain.com;
    
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### 7. SSL Certificate

```bash
certbot --nginx -d passkey.yourdomain.com
```

### 8. Start Application

```bash
# Start with PM2
pm2 start index.js --name passkey-server
pm2 save
pm2 startup
```

## Production Checklist

- [ ] Firewall configured (ports 22, 80, 443 only)
- [ ] SSL certificate installed
- [ ] Database backups configured
- [ ] PM2 auto-restart enabled
- [ ] Security updates enabled
- [ ] Monitoring configured

## iOS Integration

Your iOS app must have in its entitlements:
```
webcredentials:yourdomain.com
```

This matches the `RP_ID` setting on the server.

## Troubleshooting

### Dashboard Test Buttons Don't Work
This is expected! The dashboard runs on `passkey.yourdomain.com` but the RP_ID is `yourdomain.com`. 
Browsers prevent this for security. Your iOS app will work correctly.

### Verify Configuration
```bash
# Check if server is running
pm2 status

# View logs
pm2 logs passkey-server

# Test API
curl https://passkey.yourdomain.com/health
```

## Security Considerations

1. Always use HTTPS in production
2. Keep the server updated
3. Use strong database passwords
4. Enable automated backups
5. Monitor for suspicious activity

## Cost Estimate

- **Server**: ~€5/month (Hetzner CPX11)
- **Domain**: Varies
- **SSL**: Free (Let's Encrypt)
- **Total**: ~€5-10/month