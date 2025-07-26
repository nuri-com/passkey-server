#!/bin/bash

# Hetzner Cloud Automated Setup Script
# This script automates the entire process after you create a Hetzner account

set -e

echo "🚀 Hetzner Cloud Passkey Server Setup"
echo "====================================="
echo ""
echo "Prerequisites:"
echo "1. Create a Hetzner Cloud account at: https://console.hetzner.cloud/signup"
echo "2. Create a project in the Hetzner console"
echo "3. Generate an API token: Project → Security → API Tokens → Generate API Token"
echo "   - Give it Read & Write permissions"
echo ""
read -p "Press Enter when you have your API token ready..."
echo ""

# Get API token
read -sp "Enter your Hetzner API token: " HCLOUD_TOKEN
echo ""
export HCLOUD_TOKEN

# Configure hcloud CLI
echo "🔧 Configuring Hetzner CLI..."
hcloud context create passkey-server

# Get SSH key
echo ""
echo "📝 Setting up SSH key..."
if [ ! -f ~/.ssh/id_rsa.pub ] && [ ! -f ~/.ssh/id_ed25519.pub ]; then
    echo "No SSH key found. Creating one..."
    ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
fi

# Find the public key
if [ -f ~/.ssh/id_ed25519.pub ]; then
    SSH_KEY_PATH=~/.ssh/id_ed25519.pub
else
    SSH_KEY_PATH=~/.ssh/id_rsa.pub
fi

# Upload SSH key to Hetzner
echo "📤 Uploading SSH key to Hetzner..."
SSH_KEY_NAME="passkey-server-key-$(date +%s)"
hcloud ssh-key create --name "$SSH_KEY_NAME" --public-key-from-file "$SSH_KEY_PATH"

# Create the server
echo ""
echo "🖥️  Creating server..."
echo "Type: CPX11 (2 vCPU, 2GB RAM)"
echo "Location: nbg1 (Nuremberg, Germany)"
echo "OS: Ubuntu 22.04"
echo ""

SERVER_NAME="passkey-server-$(date +%s)"
hcloud server create \
    --name "$SERVER_NAME" \
    --type cpx11 \
    --image ubuntu-22.04 \
    --location nbg1 \
    --ssh-key "$SSH_KEY_NAME" \
    --start-after-create

echo "⏳ Waiting for server to be ready..."
sleep 30

# Get server IP
SERVER_IP=$(hcloud server describe "$SERVER_NAME" -o json | jq -r '.public_net.ipv4.ip')
echo "✅ Server created! IP: $SERVER_IP"

# Create firewall rules
echo "🔥 Setting up firewall..."
FIREWALL_NAME="passkey-firewall-$(date +%s)"
hcloud firewall create --name "$FIREWALL_NAME"
hcloud firewall add-rule "$FIREWALL_NAME" \
    --direction in --protocol tcp --port 22 --source-ips 0.0.0.0/0
hcloud firewall add-rule "$FIREWALL_NAME" \
    --direction in --protocol tcp --port 80 --source-ips 0.0.0.0/0
hcloud firewall add-rule "$FIREWALL_NAME" \
    --direction in --protocol tcp --port 443 --source-ips 0.0.0.0/0
hcloud firewall apply-to-resource "$FIREWALL_NAME" \
    --type server --server "$SERVER_NAME"

# Save server info
cat > server-info.txt << EOF
Hetzner Server Information
==========================
Server Name: $SERVER_NAME
Server IP: $SERVER_IP
SSH Command: ssh root@$SERVER_IP
API Token: (saved in hcloud context)

Next Steps:
1. Set up a domain pointing to: $SERVER_IP
2. Run: ./deploy-passkey-to-hetzner.sh
EOF

echo ""
echo "✅ Server provisioned successfully!"
echo ""
cat server-info.txt
echo ""
echo "🎯 Next: Set up a domain pointing to $SERVER_IP"
echo "   Options:"
echo "   - Use DuckDNS (free): https://www.duckdns.org"
echo "   - Use your own domain"
echo ""
echo "📝 Server info saved to: server-info.txt"