#!/bin/bash

# Generic Deployment Script for Passkey Server
# This script can be used to deploy to any Ubuntu server

set -euo pipefail

echo "🚀 Passkey Server Deployment"
echo "=========================="
echo ""
echo "This script will deploy the passkey server to your Ubuntu server."
echo "Make sure you have:"
echo "1. Ubuntu 22.04 server"
echo "2. Root or sudo access"
echo "3. Domain pointed to server IP"
echo ""

# Get configuration
read -p "Enter your domain (e.g., passkey.example.com): " DOMAIN
read -p "Enter parent domain for RP_ID (e.g., example.com): " RPID
read -p "Enter your email for SSL: " EMAIL
read -p "Enter app name (e.g., My Wallet): " RPNAME

# Generate passwords
DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
SESSION_SECRET=$(openssl rand -base64 32)

echo ""
echo "Generated secure passwords ✓"
echo ""

# Create deployment script
cat > deploy-to-server.sh << 'DEPLOY'
#!/bin/bash
set -euo pipefail

# Variables passed from parent script
DOMAIN="$1"
RPID="$2"
EMAIL="$3"
RPNAME="$4"
DB_PASSWORD="$5"
SESSION_SECRET="$6"

echo "Deploying to domain: $DOMAIN"
echo "RP ID: $RPID"

# Update system
apt update && apt upgrade -y

# Install Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

# Install other dependencies
apt install -y postgresql postgresql-contrib nginx certbot python3-certbot-nginx git build-essential

# Install PM2
npm install -g pm2

# Setup PostgreSQL
sudo -u postgres psql << EOF
CREATE DATABASE passkey_db;
CREATE USER passkey_user WITH ENCRYPTED PASSWORD '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON DATABASE passkey_db TO passkey_user;
EOF

# Create app directory
mkdir -p /var/www/passkey-server
cp -r /tmp/passkey-server/* /var/www/passkey-server/
cd /var/www/passkey-server

# Create .env file
cat > .env << ENV
DATABASE_URL=postgresql://passkey_user:$DB_PASSWORD@localhost:5432/passkey_db
PORT=3000
NODE_ENV=production
RP_ID=$RPID
RP_NAME=$RPNAME
ORIGIN=https://$DOMAIN
SESSION_SECRET=$SESSION_SECRET
ENV

# Install dependencies
npm install --production

# Start with PM2
pm2 start index.js --name passkey-server
pm2 save
pm2 startup

# Configure Nginx
cat > /etc/nginx/sites-available/passkey-server << NGINX
server {
    server_name $DOMAIN;
    
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINX

ln -sf /etc/nginx/sites-available/passkey-server /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

# Get SSL certificate
certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL

# Setup firewall
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
echo "y" | ufw enable

echo "✅ Deployment complete!"
DEPLOY

chmod +x deploy-to-server.sh

echo "📋 Deployment Summary"
echo "===================="
echo "Domain: https://$DOMAIN"
echo "RP ID: $RPID"
echo "RP Name: $RPNAME"
echo ""
echo "To deploy:"
echo "1. Copy this directory to your server"
echo "2. Run: ./deploy-to-server.sh '$DOMAIN' '$RPID' '$EMAIL' '$RPNAME' '$DB_PASSWORD' '$SESSION_SECRET'"
echo ""
echo "For iOS apps, make sure your entitlements include:"
echo "webcredentials:$RPID"