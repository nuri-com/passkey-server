#!/bin/bash

# Deploy YOUR Passkey Server (github.com/nuri-com/passkey-server) to Hetzner
# Run this after hetzner-setup.sh

set -e

echo "🚀 Deploying nuri-com/passkey-server to Hetzner"
echo "==============================================="
echo ""

# Check if server-info.txt exists
if [ ! -f server-info.txt ]; then
    echo "❌ Error: server-info.txt not found. Run hetzner-setup.sh first!"
    exit 1
fi

# Extract server IP
SERVER_IP=$(grep "Server IP:" server-info.txt | cut -d' ' -f3)

if [ -z "$SERVER_IP" ]; then
    echo "❌ Error: Could not find server IP"
    exit 1
fi

echo "📍 Server IP: $SERVER_IP"
echo ""

# Get domain info
read -p "Enter your domain (e.g., passkey.duckdns.org): " DOMAIN
read -p "Enter your email for SSL certificates: " EMAIL
read -sp "Enter a secure database password: " DB_PASSWORD
echo ""

# Create deployment script
cat > deploy-on-server.sh << EOF
#!/bin/bash
set -e

DOMAIN="$DOMAIN"
EMAIL="$EMAIL"
DB_PASSWORD="$DB_PASSWORD"

echo "🚀 Setting up nuri-com/passkey-server"
echo "Domain: \$DOMAIN"

# Update system
echo "📦 Updating system..."
apt update && apt upgrade -y

# Install dependencies
echo "📦 Installing Node.js..."
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs git

echo "📦 Installing PostgreSQL..."
apt install -y postgresql postgresql-contrib

echo "📦 Installing Nginx and Certbot..."
apt install -y nginx certbot python3-certbot-nginx

echo "📦 Installing PM2..."
npm install -g pm2

# Setup PostgreSQL
echo "🗄️ Setting up PostgreSQL..."
sudo -u postgres psql << PSQL
CREATE DATABASE passkey_db;
CREATE USER passkey_user WITH PASSWORD '\$DB_PASSWORD';
GRANT ALL PRIVILEGES ON DATABASE passkey_db TO passkey_user;
PSQL

# Clone the passkey server
echo "📥 Cloning passkey server from GitHub..."
cd /opt
git clone https://github.com/nuri-com/passkey-server.git
cd passkey-server

# Install dependencies
echo "📦 Installing Node.js dependencies..."
npm install

# Create .env file
echo "⚙️ Creating .env configuration..."
cat > .env << ENVEOF
# Database
DATABASE_URL=postgresql://passkey_user:\$DB_PASSWORD@localhost:5432/passkey_db

# Server
PORT=3000
NODE_ENV=production

# WebAuthn Configuration
DOMAIN=\$DOMAIN
RPID=\$DOMAIN
RPNAME=Nuri Wallet
ORIGIN=https://\$DOMAIN

# Add any other environment variables your server needs
ENVEOF

# Run any database migrations if your server has them
if [ -f "migrate.js" ] || [ -f "scripts/migrate.js" ]; then
    echo "🗄️ Running database migrations..."
    npm run migrate || node migrate.js || echo "No migrations found"
fi

# Start with PM2
echo "🚀 Starting server with PM2..."
pm2 start server.js --name passkey-server || pm2 start index.js --name passkey-server || pm2 start app.js --name passkey-server
pm2 save
pm2 startup systemd -u root --hp /root

# Configure Nginx
echo "🔧 Configuring Nginx..."
cat > /etc/nginx/sites-available/passkey-server << NGINX
server {
    server_name \$DOMAIN;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \\\$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \\\$host;
        proxy_cache_bypass \\\$http_upgrade;
        proxy_set_header X-Real-IP \\\$remote_addr;
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \\\$scheme;
    }
}
NGINX

ln -sf /etc/nginx/sites-available/passkey-server /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

# Get SSL certificate
echo "🔒 Setting up SSL with Let's Encrypt..."
certbot --nginx -d \$DOMAIN --non-interactive --agree-tos -m \$EMAIL

# Setup firewall
echo "🔥 Configuring firewall..."
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
echo "y" | ufw enable

echo ""
echo "✅ Deployment complete!"
echo "🔐 Passkey server: https://\$DOMAIN"
echo ""
echo "📊 Check server status:"
echo "   pm2 status"
echo "   pm2 logs passkey-server"
echo "   systemctl status nginx"
EOF

# Copy deployment script to server
echo "📤 Copying deployment script to server..."
scp deploy-on-server.sh root@$SERVER_IP:/root/

# Execute deployment
echo "🚀 Running deployment on server..."
ssh root@$SERVER_IP "chmod +x /root/deploy-on-server.sh && /root/deploy-on-server.sh"

# Update iOS app configuration
echo ""
echo "✅ Deployment complete!"
echo ""
echo "📱 Now update your iOS app:"
echo ""
echo "In PasskeyAuthenticationService.swift, change:"
echo "   return \"https://$DOMAIN\""
echo ""
echo "🔐 Your passkey server is live at: https://$DOMAIN"
echo ""
echo "🧪 Test your server:"
echo "   curl https://$DOMAIN/health"
echo "   curl https://$DOMAIN/generate-authentication-options"
echo ""
echo "📊 Server management:"
echo "   SSH: ssh root@$SERVER_IP"
echo "   Logs: pm2 logs passkey-server"
echo "   Status: pm2 status"
echo "   Restart: pm2 restart passkey-server"

# Cleanup
rm -f deploy-on-server.sh

# Save deployment info
cat > deployment-info.txt << INFO
Passkey Server Deployment Info
==============================
Server IP: $SERVER_IP
Domain: https://$DOMAIN
Repository: https://github.com/nuri-com/passkey-server

SSH Access: ssh root@$SERVER_IP
Server Logs: pm2 logs passkey-server
Server Status: pm2 status

iOS App Configuration:
In PasskeyAuthenticationService.swift:
return "https://$DOMAIN"
INFO

echo ""
echo "📝 Deployment info saved to: deployment-info.txt"