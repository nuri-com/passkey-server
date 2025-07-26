# Deploy Passkey Server to Hetzner Cloud

## Quick Setup Guide

### 1. Create Hetzner Cloud Account
- Go to [https://www.hetzner.com/cloud](https://www.hetzner.com/cloud)
- Sign up (they often have free credits for new users)
- Create a new project

### 2. Create a Server
- Click "New Server"
- Choose:
  - Location: Closest to you (e.g., Nuremberg for EU)
  - Image: **Ubuntu 22.04**
  - Type: **CPX11** (2 vCPU, 2GB RAM - €4.15/month)
  - Add your SSH key (optional but recommended)
  - Name: `passkey-server`

### 3. Get a Domain (Quick Options)
1. **Free subdomain**: Use [DuckDNS](https://www.duckdns.org) - instant setup
2. **Your domain**: Point an A record to your server's IP
3. **Hetzner DNS**: Free with server, reliable

### 4. Quick Server Setup Script

Once your server is created, SSH into it and run:

```bash
# Connect to your server
ssh root@YOUR_SERVER_IP

# Run this one-liner to set up everything:
curl -fsSL https://raw.githubusercontent.com/nuri-com/passkey-server-setup/main/setup.sh | bash
```

If you prefer manual setup:

```bash
#!/bin/bash
# Save this as setup-passkey-server.sh

# Update system
apt update && apt upgrade -y

# Install Node.js 18
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs

# Install PostgreSQL
apt install -y postgresql postgresql-contrib

# Install nginx and certbot
apt install -y nginx certbot python3-certbot-nginx

# Install PM2 for process management
npm install -g pm2

# Create app directory
mkdir -p /var/www/passkey-server
cd /var/www/passkey-server

# Clone your passkey server (or upload it)
# git clone YOUR_PASSKEY_SERVER_REPO .
# OR upload your local server files

# Install dependencies
npm install

# Setup PostgreSQL
sudo -u postgres psql << EOF
CREATE DATABASE passkey_db;
CREATE USER passkey_user WITH PASSWORD 'secure_password_here';
GRANT ALL PRIVILEGES ON DATABASE passkey_db TO passkey_user;
EOF

# Create .env file
cat > .env << EOF
DATABASE_URL=postgresql://passkey_user:secure_password_here@localhost:5432/passkey_db
PORT=3000
NODE_ENV=production
RPID=your-domain.com
RPNAME=Nuri Wallet
ORIGIN=https://your-domain.com
EOF

# Setup PM2 to run the server
pm2 start server.js --name passkey-server
pm2 save
pm2 startup

# Configure nginx
cat > /etc/nginx/sites-available/passkey-server << 'EOF'
server {
    server_name your-domain.com;

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
EOF

# Enable the site
ln -s /etc/nginx/sites-available/passkey-server /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx

# Get SSL certificate
certbot --nginx -d your-domain.com --non-interactive --agree-tos -m your-email@example.com

echo "✅ Server setup complete!"
echo "🔐 Your passkey server is now running at https://your-domain.com"
```

### 5. Quick Domain Setup with DuckDNS (Free)

1. Go to [https://www.duckdns.org](https://www.duckdns.org)
2. Sign in with GitHub/Google
3. Create a subdomain (e.g., `nuri-passkey`)
4. Set the IP to your Hetzner server IP
5. Your domain: `nuri-passkey.duckdns.org`

### 6. Update Your iOS App

In `PasskeyAuthenticationService.swift`:
```swift
private var baseURL: String {
    return "https://nuri-passkey.duckdns.org" // or your domain
}
```

## Estimated Time: 15-20 minutes

## Total Cost: €4.15/month (Hetzner CPX11)

## Security Checklist
- [ ] Change default PostgreSQL password
- [ ] Set up firewall (ufw)
- [ ] Enable automatic security updates
- [ ] Set up monitoring (optional)