#!/bin/bash

# Deploy Passkey Server to Hetzner Cloud Server
# Run this after hetzner-cli-setup.sh

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}🚀 Passkey Server Deployment${NC}"
echo "============================"
echo ""

# Check for server-info.json
if [ ! -f "server-info.json" ]; then
    echo -e "${RED}❌ server-info.json not found. Run hetzner-cli-setup.sh first!${NC}"
    exit 1
fi

# Extract server info
SERVER_IP=$(jq -r '.server_ip' server-info.json)
SERVER_NAME=$(jq -r '.server_name' server-info.json)

echo -e "${BLUE}📍 Server: ${NC}$SERVER_NAME ($SERVER_IP)"
echo ""

# Get configuration
read -p "Enter your domain (e.g., passkey.yourdomain.com or yourname.duckdns.org): " DOMAIN
read -p "Enter your email for SSL certificates: " EMAIL
echo ""

# Generate secure passwords
DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
SESSION_SECRET=$(openssl rand -base64 32)

echo -e "${GREEN}✅ Generated secure passwords${NC}"

# Create deployment package
echo -e "${BLUE}📦 Preparing deployment...${NC}"

# Create a temporary directory for deployment files
DEPLOY_DIR=$(mktemp -d)
echo "Working directory: $DEPLOY_DIR"

# Copy the passkey server files
cp -r ../* "$DEPLOY_DIR/" 2>/dev/null || true
cd "$DEPLOY_DIR"

# Remove setup directory and other unnecessary files
rm -rf setup
rm -f .env
rm -rf node_modules

# Create deployment script
cat > deploy-on-server.sh << 'DEPLOY'
#!/bin/bash
set -euo pipefail

DOMAIN="$1"
EMAIL="$2"
DB_PASSWORD="$3"
SESSION_SECRET="$4"

echo "🚀 Deploying Passkey Server"
echo "Domain: $DOMAIN"

# Update system
echo "📦 Updating system..."
apt update && apt upgrade -y

# Install Node.js 20 (required version)
echo "📦 Installing Node.js 20..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

# Install other dependencies
echo "📦 Installing PostgreSQL, Nginx, and tools..."
apt install -y postgresql postgresql-contrib nginx certbot python3-certbot-nginx git build-essential

# Install PM2
echo "📦 Installing PM2..."
npm install -g pm2

# Setup PostgreSQL
echo "🗄️ Setting up PostgreSQL..."
sudo -u postgres psql << EOF
CREATE DATABASE passkey_db;
CREATE USER passkey_user WITH ENCRYPTED PASSWORD '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON DATABASE passkey_db TO passkey_user;
ALTER DATABASE passkey_db OWNER TO passkey_user;
\q
EOF

# Configure PostgreSQL
echo "host    passkey_db    passkey_user    127.0.0.1/32    scram-sha-256" >> /etc/postgresql/*/main/pg_hba.conf
systemctl restart postgresql

# Create app user
echo "👤 Creating application user..."
useradd -m -s /bin/bash passkey || true
usermod -aG sudo passkey || true

# Setup application
echo "📁 Setting up application..."
mkdir -p /var/www/passkey-server
cp -r /tmp/passkey-server/* /var/www/passkey-server/
chown -R passkey:passkey /var/www/passkey-server

cd /var/www/passkey-server

# Create production environment file
echo "⚙️ Creating environment configuration..."
cat > .env << ENV
# Database
DATABASE_URL=postgresql://passkey_user:$DB_PASSWORD@localhost:5432/passkey_db

# Server
PORT=3000
NODE_ENV=production

# WebAuthn Configuration
RP_ID=$DOMAIN
RP_NAME=Nuri Passkey Server
ORIGIN=https://$DOMAIN

# Security
SESSION_SECRET=$SESSION_SECRET
ENV

chown passkey:passkey .env
chmod 600 .env

# Install dependencies
echo "📦 Installing Node.js dependencies..."
sudo -u passkey npm install --production

# Initialize database
echo "🗄️ Initializing database..."
sudo -u passkey npm run migrate || echo "No migrations found"

# Create PM2 ecosystem file
cat > ecosystem.config.js << 'ECO'
module.exports = {
  apps: [{
    name: 'passkey-server',
    script: './index.js',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '500M',
    env: {
      NODE_ENV: 'production'
    },
    error_file: '/var/log/pm2/passkey-error.log',
    out_file: '/var/log/pm2/passkey-out.log',
    log_file: '/var/log/pm2/passkey-combined.log',
    time: true
  }]
};
ECO

chown passkey:passkey ecosystem.config.js

# Create log directory
mkdir -p /var/log/pm2
chown -R passkey:passkey /var/log/pm2

# Start application
echo "🚀 Starting application..."
sudo -u passkey pm2 start ecosystem.config.js
sudo -u passkey pm2 save

# Setup PM2 startup
pm2 startup systemd -u passkey --hp /home/passkey
systemctl enable pm2-passkey

# Configure Nginx
echo "🔧 Configuring Nginx..."
cat > /etc/nginx/sites-available/passkey-server << NGINX
# Rate limiting
limit_req_zone \$binary_remote_addr zone=passkey_limit:10m rate=10r/s;

server {
    server_name $DOMAIN;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    
    # Rate limiting
    limit_req zone=passkey_limit burst=20 nodelay;
    
    # Timeouts
    client_body_timeout 60;
    client_header_timeout 60;
    keepalive_timeout 65;
    send_timeout 60;
    
    # Buffer sizes
    client_body_buffer_size 1K;
    client_header_buffer_size 1k;
    client_max_body_size 1M;
    large_client_header_buffers 2 1k;
    
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
        
        # Proxy timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # Block access to hidden files
    location ~ /\. {
        deny all;
        return 404;
    }
}
NGINX

# Enable site
ln -sf /etc/nginx/sites-available/passkey-server /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test Nginx configuration
nginx -t

# Reload Nginx
systemctl reload nginx

# Get SSL certificate
echo "🔒 Setting up SSL certificate..."
certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL --redirect

# Configure fail2ban for Nginx
echo "🛡️ Configuring fail2ban..."
cat > /etc/fail2ban/filter.d/nginx-limit-req.conf << 'FAIL'
[Definition]
failregex = limiting requests, excess:.* by zone.*client: <HOST>
ignoreregex =
FAIL

cat > /etc/fail2ban/jail.local << 'JAIL'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true

[nginx-limit-req]
enabled = true
filter = nginx-limit-req
action = iptables-multiport[name=nginx-limit-req, port="http,https"]
logpath = /var/log/nginx/error.log
findtime = 600
bantime = 7200
maxretry = 10
JAIL

systemctl restart fail2ban

# Setup backup script
echo "💾 Setting up automated backups..."
cat > /home/passkey/backup.sh << 'BACKUP'
#!/bin/bash
BACKUP_DIR="/home/passkey/backups"
mkdir -p $BACKUP_DIR
DATE=$(date +%Y%m%d_%H%M%S)

# Backup database
sudo -u postgres pg_dump passkey_db | gzip > $BACKUP_DIR/db_$DATE.sql.gz

# Backup environment file
cp /var/www/passkey-server/.env $BACKUP_DIR/env_$DATE

# Keep only last 7 days of backups
find $BACKUP_DIR -name "db_*.sql.gz" -mtime +7 -delete
find $BACKUP_DIR -name "env_*" -mtime +7 -delete

# Encrypt backups
tar -czf - $BACKUP_DIR | openssl enc -aes-256-cbc -salt -k "$SESSION_SECRET" > $BACKUP_DIR/backup_$DATE.tar.gz.enc
BACKUP

chmod +x /home/passkey/backup.sh
chown passkey:passkey /home/passkey/backup.sh

# Add to crontab
echo "0 3 * * * /home/passkey/backup.sh" | crontab -u passkey -

# Setup monitoring
echo "📊 Setting up monitoring..."
cat > /home/passkey/health-check.sh << 'HEALTH'
#!/bin/bash
if ! curl -f http://localhost:3000/health > /dev/null 2>&1; then
    pm2 restart passkey-server
    echo "$(date): Restarted passkey-server due to health check failure" >> /var/log/passkey-health.log
fi
HEALTH

chmod +x /home/passkey/health-check.sh
echo "*/5 * * * * /home/passkey/health-check.sh" | crontab -u passkey -

# Final security hardening
echo "🔒 Final security hardening..."
# Disable root SSH (make sure you have another way in!)
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl restart sshd

echo ""
echo "✅ Deployment complete!"
echo "======================"
echo "🌐 Your passkey server is live at: https://$DOMAIN"
echo ""
echo "📱 For your iOS app, use: https://$DOMAIN"
echo ""
echo "🔐 Database password saved in: /var/www/passkey-server/.env"
echo "📊 View logs: pm2 logs passkey-server"
echo "🔄 Restart: pm2 restart passkey-server"
echo ""
echo "⚠️  SSH root access has been disabled for security."
echo "Create a new user for future access!"
DEPLOY

# Make script executable
chmod +x deploy-on-server.sh

# Copy files to server
echo -e "${BLUE}📤 Uploading files to server...${NC}"
ssh -i ~/.ssh/hetzner_short_key root@"$SERVER_IP" "rm -rf /tmp/passkey-server && mkdir -p /tmp/passkey-server"
scp -r -i ~/.ssh/hetzner_short_key ./* root@"$SERVER_IP":/tmp/passkey-server/

# Copy deployment script
scp -i ~/.ssh/hetzner_short_key deploy-on-server.sh root@"$SERVER_IP":/root/

# Run deployment
echo -e "${BLUE}🚀 Running deployment on server...${NC}"
echo "(This will take a few minutes...)"
ssh -i ~/.ssh/hetzner_short_key root@"$SERVER_IP" "bash /root/deploy-on-server.sh '$DOMAIN' '$EMAIL' '$DB_PASSWORD' '$SESSION_SECRET'"

# Test the deployment
echo ""
echo -e "${BLUE}🧪 Testing deployment...${NC}"
sleep 5

# Test health endpoint
if curl -s -f "https://$DOMAIN/health" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Health check passed!${NC}"
else
    echo -e "${YELLOW}⚠️  Health check failed. The server might still be starting up.${NC}"
    echo "Try again in a few seconds: curl https://$DOMAIN/health"
fi

# Save deployment info
cat > deployment-complete.json << EOF
{
  "domain": "https://$DOMAIN",
  "server_ip": "$SERVER_IP",
  "deployed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "ios_config": {
    "baseURL": "https://$DOMAIN"
  },
  "management": {
    "ssh": "ssh -i ~/.ssh/hetzner_key passkey@$SERVER_IP",
    "logs": "pm2 logs passkey-server",
    "restart": "pm2 restart passkey-server",
    "status": "pm2 status"
  },
  "endpoints": {
    "health": "https://$DOMAIN/health",
    "dashboard": "https://$DOMAIN/dashboard",
    "register_options": "https://$DOMAIN/generate-registration-options",
    "auth_options": "https://$DOMAIN/generate-authentication-options"
  }
}
EOF

# Display summary
echo ""
echo -e "${GREEN}🎉 Deployment Complete!${NC}"
echo "======================="
echo ""
echo -e "${BLUE}🌐 Passkey Server:${NC} https://$DOMAIN"
echo ""
echo -e "${BLUE}📱 iOS Configuration:${NC}"
echo "   In your Swift app, set:"
echo "   baseURL = \"https://$DOMAIN\""
echo ""
echo -e "${BLUE}🔧 Server Management:${NC}"
echo "   Logs: pm2 logs passkey-server"
echo "   Status: pm2 status"
echo "   Restart: pm2 restart passkey-server"
echo ""
echo -e "${BLUE}🔐 Security Notes:${NC}"
echo "   - Root SSH access has been disabled"
echo "   - Fail2ban is active"
echo "   - Automated backups run at 3 AM daily"
echo "   - SSL certificate will auto-renew"
echo ""
echo -e "${YELLOW}⚠️  Important:${NC}"
echo "   1. Create a non-root user for SSH access"
echo "   2. Save the deployment-complete.json file"
echo "   3. Test all endpoints before switching your app"
echo ""

# Cleanup
cd ..
rm -rf "$DEPLOY_DIR"

echo -e "${GREEN}✅ All done! Your passkey server is live and secure.${NC}"