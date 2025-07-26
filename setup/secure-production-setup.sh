#!/bin/bash

# Secure Production Setup for Passkey Server
# This script properly deploys YOUR actual passkey server with security best practices

set -euo pipefail

echo "🔐 Secure Passkey Server Production Setup"
echo "========================================"

# Security check
if [[ $EUID -eq 0 ]]; then
   echo "❌ Do not run this script as root for initial setup" 
   exit 1
fi

# Collect information securely
echo "📝 Server Configuration"
read -p "Enter your domain (e.g., passkey.yourdomain.com): " DOMAIN
read -p "Enter your email for SSL certificates: " EMAIL
read -p "Enter your SSH IP for firewall whitelist (your current IP): " SSH_IP

# Generate secure passwords
DB_PASSWORD=$(openssl rand -base64 32)
APP_SECRET=$(openssl rand -base64 32)

echo "✅ Generated secure passwords"

# Create deployment package
echo "📦 Creating deployment package..."

cat > deploy-secure.sh << 'DEPLOY'
#!/bin/bash
set -euo pipefail

DOMAIN="$1"
EMAIL="$2"
DB_PASSWORD="$3"
APP_SECRET="$4"
SSH_IP="$5"

# Create non-root user for app
useradd -m -s /bin/bash passkey
usermod -aG sudo passkey

# Update and secure system
apt update && apt upgrade -y
apt install -y ufw fail2ban unattended-upgrades

# Configure automatic security updates
dpkg-reconfigure -plow unattended-upgrades

# Install Node.js 20 (required version)
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

# Install other dependencies
apt install -y postgresql postgresql-contrib nginx certbot python3-certbot-nginx git

# Secure PostgreSQL
sudo -u postgres psql << EOF
CREATE DATABASE passkey_db;
CREATE USER passkey_user WITH ENCRYPTED PASSWORD '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON DATABASE passkey_db TO passkey_user;
ALTER DATABASE passkey_db OWNER TO passkey_user;
EOF

# Configure PostgreSQL for security
echo "host    passkey_db    passkey_user    127.0.0.1/32    scram-sha-256" >> /etc/postgresql/*/main/pg_hba.conf
systemctl restart postgresql

# Setup application directory
mkdir -p /var/www/passkey-server
chown passkey:passkey /var/www/passkey-server

# Copy application files (assuming they're uploaded to /tmp/passkey-server)
cp -r /tmp/passkey-server/* /var/www/passkey-server/
chown -R passkey:passkey /var/www/passkey-server

cd /var/www/passkey-server

# Install dependencies as non-root user
sudo -u passkey npm install --production

# Create secure environment file
sudo -u passkey cat > .env << ENV
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
SESSION_SECRET=$APP_SECRET
ENV

# Initialize database
sudo -u passkey npm run migrate || echo "No migrations found"

# Install PM2 globally
npm install -g pm2

# Start application as passkey user
sudo -u passkey pm2 start index.js --name passkey-server
sudo -u passkey pm2 save

# Generate PM2 startup script
pm2 startup systemd -u passkey --hp /home/passkey
systemctl enable pm2-passkey

# Configure Nginx with security headers
cat > /etc/nginx/sites-available/passkey-server << 'NGINX'
server {
    server_name $DOMAIN;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline';" always;
    
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
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
NGINX

# Enable site
ln -sf /etc/nginx/sites-available/passkey-server /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

# Setup SSL
certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL

# Configure firewall with specific IP for SSH
ufw default deny incoming
ufw default allow outgoing
ufw allow from $SSH_IP to any port 22
ufw allow 80/tcp
ufw allow 443/tcp
echo "y" | ufw enable

# Configure fail2ban
cat > /etc/fail2ban/jail.local << 'FAIL2BAN'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log

[nginx-limit-req]
enabled = true
filter = nginx-limit-req
port = http,https
logpath = /var/log/nginx/error.log
FAIL2BAN

systemctl restart fail2ban

# Setup backup script
cat > /home/passkey/backup.sh << 'BACKUP'
#!/bin/bash
BACKUP_DIR="/home/passkey/backups"
mkdir -p $BACKUP_DIR
DATE=$(date +%Y%m%d_%H%M%S)

# Backup database
sudo -u postgres pg_dump passkey_db | gzip > $BACKUP_DIR/db_$DATE.sql.gz

# Keep only last 7 days of backups
find $BACKUP_DIR -name "db_*.sql.gz" -mtime +7 -delete
BACKUP

chmod +x /home/passkey/backup.sh
echo "0 3 * * * /home/passkey/backup.sh" | crontab -u passkey -

echo "✅ Secure deployment complete!"
DEPLOY

# Create upload script
cat > upload-and-deploy.sh << 'UPLOAD'
#!/bin/bash
set -euo pipefail

SERVER_IP="$1"
DOMAIN="$2"
EMAIL="$3"
DB_PASSWORD="$4"
APP_SECRET="$5"
SSH_IP="$6"

echo "📤 Uploading passkey server..."

# Create temporary directory on server
ssh root@$SERVER_IP "mkdir -p /tmp/passkey-server"

# Upload current passkey server (excluding node_modules)
rsync -avz --exclude='node_modules' --exclude='.git' \
  ../* root@$SERVER_IP:/tmp/passkey-server/

# Upload and run deployment script
scp deploy-secure.sh root@$SERVER_IP:/tmp/
ssh root@$SERVER_IP "bash /tmp/deploy-secure.sh '$DOMAIN' '$EMAIL' '$DB_PASSWORD' '$APP_SECRET' '$SSH_IP'"

echo "✅ Deployment complete!"
echo ""
echo "🔐 Important Information (SAVE THIS!):"
echo "====================================="
echo "Domain: https://$DOMAIN"
echo "Database Password: $DB_PASSWORD"
echo "App Secret: $APP_SECRET"
echo ""
echo "📱 iOS Configuration:"
echo "In your Swift app, set baseURL to: https://$DOMAIN"
echo ""
echo "🔧 Server Management:"
echo "SSH: ssh root@$SERVER_IP (only from IP: $SSH_IP)"
echo "Logs: pm2 logs passkey-server"
echo "Status: pm2 status"
echo "Restart: pm2 restart passkey-server"
echo ""
echo "🔒 Security Notes:"
echo "- Firewall configured (SSH restricted to your IP)"
echo "- Fail2ban active"
echo "- Automatic security updates enabled"
echo "- Daily backups at 3 AM"
UPLOAD

chmod +x deploy-secure.sh upload-and-deploy.sh

echo ""
echo "✅ Setup scripts created!"
echo ""
echo "📋 Next Steps:"
echo "1. Review the generated scripts"
echo "2. Get your server IP from Hetzner"
echo "3. Run: ./upload-and-deploy.sh SERVER_IP '$DOMAIN' '$EMAIL' '$DB_PASSWORD' '$APP_SECRET' '$SSH_IP'"
echo ""
echo "🔐 Credentials saved to: credentials.txt"

# Save credentials securely
cat > credentials.txt << CREDS
Passkey Server Credentials
=========================
Domain: $DOMAIN
Email: $EMAIL
Database Password: $DB_PASSWORD
App Secret: $APP_SECRET
SSH Allowed IP: $SSH_IP

⚠️ KEEP THIS FILE SECURE!
CREDS

chmod 600 credentials.txt