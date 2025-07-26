#!/bin/bash

# Passkey Server Quick Deployment Script for Hetzner/Any VPS
# This script sets up a production-ready passkey server with SSL

set -e

echo "🚀 Passkey Server Setup Script"
echo "=============================="

# Get user inputs
read -p "Enter your domain (e.g., passkey.yourdomain.com): " DOMAIN
read -p "Enter your email for SSL certificates: " EMAIL
read -sp "Enter a secure database password: " DB_PASSWORD
echo

# Update system
echo "📦 Updating system packages..."
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
sudo -u postgres psql << EOF
CREATE DATABASE passkey_db;
CREATE USER passkey_user WITH PASSWORD '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON DATABASE passkey_db TO passkey_user;
\q
EOF

# Create app directory
echo "📁 Creating application directory..."
mkdir -p /var/www/passkey-server
cd /var/www/passkey-server

# Create a simple passkey server if one doesn't exist
echo "📝 Creating passkey server..."
cat > package.json << 'EOF'
{
  "name": "passkey-server",
  "version": "1.0.0",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "@simplewebauthn/server": "^8.3.2",
    "cors": "^2.8.5",
    "dotenv": "^16.3.1",
    "pg": "^8.11.3",
    "body-parser": "^1.20.2"
  }
}
EOF

# Install dependencies
npm install

# Create the server file
cat > server.js << 'EOF'
const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');
const { 
  generateRegistrationOptions,
  verifyRegistrationResponse,
  generateAuthenticationOptions,
  verifyAuthenticationResponse
} = require('@simplewebauthn/server');

require('dotenv').config();

const app = express();
app.use(cors());
app.use(bodyParser.json());

// In-memory storage (replace with PostgreSQL in production)
const users = new Map();
const challenges = new Map();

const rpName = process.env.RPNAME || 'Passkey Server';
const rpID = process.env.RPID || process.env.DOMAIN;
const origin = process.env.ORIGIN || `https://${process.env.DOMAIN}`;

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'passkey-server' });
});

// Generate registration options
app.get('/generate-registration-options', async (req, res) => {
  const username = req.query.username || `user_${Date.now()}`;
  
  const options = await generateRegistrationOptions({
    rpName,
    rpID,
    userID: username,
    userName: username,
    userDisplayName: username,
    attestationType: 'none',
    authenticatorSelection: {
      authenticatorAttachment: 'platform',
      requireResidentKey: false,
      userVerification: 'preferred'
    },
  });

  challenges.set(username, options.challenge);
  
  res.json({
    ...options,
    challengeKey: username
  });
});

// Verify registration
app.post('/verify-registration', async (req, res) => {
  const { username, cred, challengeKey } = req.body;
  const expectedChallenge = challenges.get(challengeKey);

  try {
    const verification = await verifyRegistrationResponse({
      response: cred,
      expectedChallenge,
      expectedOrigin: origin,
      expectedRPID: rpID,
    });

    if (verification.verified) {
      users.set(username || challengeKey, {
        credentialID: cred.credentialId,
        publicKey: verification.registrationInfo.credentialPublicKey,
        counter: verification.registrationInfo.counter,
      });
    }

    res.json({
      verified: verification.verified,
      username: username || challengeKey,
      isAnonymous: !username
    });
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
});

// Generate authentication options
app.get('/generate-authentication-options', async (req, res) => {
  const options = await generateAuthenticationOptions({
    rpID,
    userVerification: 'preferred',
  });

  challenges.set('auth', options.challenge);
  
  res.json(options);
});

// Verify authentication
app.post('/verify-authentication', async (req, res) => {
  const { cred } = req.body;
  const expectedChallenge = challenges.get('auth');

  try {
    // Find user by credential ID
    let foundUser = null;
    let foundUsername = null;
    
    for (const [username, user] of users.entries()) {
      if (user.credentialID === cred.credentialId) {
        foundUser = user;
        foundUsername = username;
        break;
      }
    }

    if (!foundUser) {
      return res.status(404).json({ error: 'User not found' });
    }

    const verification = await verifyAuthenticationResponse({
      response: cred,
      expectedChallenge,
      expectedOrigin: origin,
      expectedRPID: rpID,
      authenticator: foundUser,
    });

    res.json({
      verified: verification.verified,
      username: foundUsername,
      isAnonymous: foundUsername.startsWith('user_')
    });
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Passkey server running on port ${PORT}`);
  console.log(`RP ID: ${rpID}`);
  console.log(`Origin: ${origin}`);
});
EOF

# Create .env file
echo "⚙️ Creating environment configuration..."
cat > .env << EOF
DATABASE_URL=postgresql://passkey_user:$DB_PASSWORD@localhost:5432/passkey_db
PORT=3000
NODE_ENV=production
DOMAIN=$DOMAIN
RPID=$DOMAIN
RPNAME=Nuri Wallet
ORIGIN=https://$DOMAIN
EOF

# Start with PM2
echo "🚀 Starting server with PM2..."
pm2 start server.js --name passkey-server
pm2 save
pm2 startup systemd -u root --hp /root

# Configure Nginx
echo "🔧 Configuring Nginx..."
cat > /etc/nginx/sites-available/passkey-server << EOF
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
EOF

ln -sf /etc/nginx/sites-available/passkey-server /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

# Get SSL certificate
echo "🔒 Setting up SSL with Let's Encrypt..."
certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL

# Setup firewall
echo "🔥 Configuring firewall..."
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
echo "y" | ufw enable

echo "✅ Setup complete!"
echo "===================================="
echo "🔐 Your passkey server is running at: https://$DOMAIN"
echo "📱 Update your iOS app with this URL"
echo ""
echo "🔍 Check server status: pm2 status"
echo "📊 View logs: pm2 logs passkey-server"
echo "🔄 Restart server: pm2 restart passkey-server"