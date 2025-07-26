#!/bin/bash

# Complete Hetzner Cloud Server Setup via CLI
# This script creates and configures a passkey server entirely through CLI

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Hetzner Cloud Passkey Server Setup via CLI${NC}"
echo "=============================================="
echo ""

# Check if hcloud is installed
if ! command -v hcloud &> /dev/null; then
    echo -e "${RED}❌ hcloud CLI not found. Please install it first:${NC}"
    echo "brew install hcloud"
    exit 1
fi

# Check if API token is set
if [ -z "${HCLOUD_TOKEN:-}" ]; then
    echo -e "${YELLOW}📝 API Token not found in environment${NC}"
    echo "Please enter your Hetzner API token:"
    read -sp "Token: " HCLOUD_TOKEN
    echo ""
    export HCLOUD_TOKEN
fi

# Test API connection
echo -e "${BLUE}🔧 Testing API connection...${NC}"
if ! hcloud server-type list > /dev/null 2>&1; then
    echo -e "${RED}❌ Failed to connect to Hetzner API. Check your token.${NC}"
    exit 1
fi
echo -e "${GREEN}✅ API connection successful${NC}"

# Configuration
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SERVER_NAME="passkey-server-${TIMESTAMP}"
SERVER_TYPE="cpx11"  # 2 vCPU, 2GB RAM
LOCATION="nbg1"      # Nuremberg, Germany (change if needed)
IMAGE="ubuntu-22.04"

echo ""
echo -e "${BLUE}📋 Server Configuration:${NC}"
echo "  Name: $SERVER_NAME"
echo "  Type: $SERVER_TYPE (2 vCPU, 2GB RAM, €4.15/month)"
echo "  Location: $LOCATION"
echo "  OS: $IMAGE"
echo ""

# List available SSH keys
echo -e "${BLUE}🔑 Available SSH Keys:${NC}"
hcloud ssh-key list
echo ""

# Get SSH key selection
echo "Enter the ID or name of the SSH key to use:"
read -p "SSH Key: " SSH_KEY

# Create firewall first
echo -e "${BLUE}🔥 Creating firewall...${NC}"
FIREWALL_NAME="passkey-firewall-${TIMESTAMP}"

# Create firewall
hcloud firewall create --name "$FIREWALL_NAME" \
    --label purpose=passkey-server

# Add firewall rules
echo "Adding firewall rules..."

# SSH (will be restricted later)
hcloud firewall add-rule "$FIREWALL_NAME" \
    --description "SSH" \
    --direction in \
    --port 22 \
    --protocol tcp \
    --source-ips 0.0.0.0/0 \
    --source-ips ::/0

# HTTP
hcloud firewall add-rule "$FIREWALL_NAME" \
    --description "HTTP" \
    --direction in \
    --port 80 \
    --protocol tcp \
    --source-ips 0.0.0.0/0 \
    --source-ips ::/0

# HTTPS
hcloud firewall add-rule "$FIREWALL_NAME" \
    --description "HTTPS" \
    --direction in \
    --port 443 \
    --protocol tcp \
    --source-ips 0.0.0.0/0 \
    --source-ips ::/0

echo -e "${GREEN}✅ Firewall created${NC}"

# Create the server
echo ""
echo -e "${BLUE}🖥️  Creating server...${NC}"
hcloud server create \
    --name "$SERVER_NAME" \
    --type "$SERVER_TYPE" \
    --image "$IMAGE" \
    --location "$LOCATION" \
    --ssh-key "$SSH_KEY" \
    --firewall "$FIREWALL_NAME" \
    --label purpose=passkey-server \
    --label env=production

echo -e "${GREEN}✅ Server creation initiated${NC}"

# Wait for server to be ready
echo -e "${BLUE}⏳ Waiting for server to be ready...${NC}"
sleep 10

# Get server details
SERVER_ID=$(hcloud server list --selector "name=$SERVER_NAME" -o noheader | awk '{print $1}')
SERVER_STATUS=""

# Wait for running status
while [ "$SERVER_STATUS" != "running" ]; do
    SERVER_STATUS=$(hcloud server describe "$SERVER_ID" -o json | jq -r '.status')
    echo -ne "\rServer status: $SERVER_STATUS"
    sleep 2
done
echo ""

# Get server IP
SERVER_IP=$(hcloud server describe "$SERVER_ID" -o json | jq -r '.public_net.ipv4.ip')
echo -e "${GREEN}✅ Server is ready!${NC}"
echo -e "${BLUE}📍 Server IP: ${NC}$SERVER_IP"

# Create a cloud-init script for initial setup
echo ""
echo -e "${BLUE}📝 Creating initial setup script...${NC}"

cat > initial-setup.sh << 'INIT'
#!/bin/bash
set -euo pipefail

# Wait for cloud-init to complete
while [ ! -f /var/lib/cloud/instance/boot-finished ]; do
    echo "Waiting for cloud-init to finish..."
    sleep 2
done

# Update system
apt update && apt upgrade -y

# Install essential packages
apt install -y curl wget git vim htop ufw fail2ban

# Configure fail2ban
systemctl enable fail2ban
systemctl start fail2ban

# Basic UFW setup (will be refined later)
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
echo "y" | ufw enable

echo "✅ Initial setup complete"
INIT

# Wait a bit more for SSH to be ready
echo -e "${BLUE}⏳ Waiting for SSH to be ready...${NC}"
sleep 20

# Test SSH connection
MAX_RETRIES=30
RETRY_COUNT=0
while ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i ~/.ssh/hetzner_key root@"$SERVER_IP" "echo 'SSH test successful'" 2>/dev/null; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
        echo -e "${RED}❌ Failed to connect via SSH after $MAX_RETRIES attempts${NC}"
        exit 1
    fi
    echo -ne "\rWaiting for SSH... attempt $RETRY_COUNT/$MAX_RETRIES"
    sleep 5
done
echo ""
echo -e "${GREEN}✅ SSH connection established${NC}"

# Copy and run initial setup
echo -e "${BLUE}🚀 Running initial server setup...${NC}"
scp -o StrictHostKeyChecking=no -i ~/.ssh/hetzner_key initial-setup.sh root@"$SERVER_IP":/root/
ssh -o StrictHostKeyChecking=no -i ~/.ssh/hetzner_key root@"$SERVER_IP" "chmod +x /root/initial-setup.sh && /root/initial-setup.sh"

# Save server information
cat > server-info.json << EOF
{
  "server_name": "$SERVER_NAME",
  "server_id": "$SERVER_ID",
  "server_ip": "$SERVER_IP",
  "server_type": "$SERVER_TYPE",
  "location": "$LOCATION",
  "firewall": "$FIREWALL_NAME",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "ssh_command": "ssh -i ~/.ssh/hetzner_key root@$SERVER_IP"
}
EOF

# Display summary
echo ""
echo -e "${GREEN}✅ Server successfully created!${NC}"
echo "======================================"
echo -e "${BLUE}Server Details:${NC}"
echo "  Name: $SERVER_NAME"
echo "  ID: $SERVER_ID"
echo "  IP: $SERVER_IP"
echo "  Type: $SERVER_TYPE"
echo "  Location: $LOCATION"
echo ""
echo -e "${BLUE}SSH Access:${NC}"
echo "  ssh -i ~/.ssh/hetzner_key root@$SERVER_IP"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "1. Set up DNS record pointing to: $SERVER_IP"
echo "2. Run the deployment script: ./deploy-passkey-server.sh"
echo ""
echo -e "${YELLOW}⚠️  Important:${NC}"
echo "- Server info saved to: server-info.json"
echo "- Initial firewall is configured but SSH is open to all"
echo "- Remember to restrict SSH access after setup"
echo ""

# Cleanup
rm -f initial-setup.sh

# Ask about DNS setup
echo -e "${BLUE}📌 DNS Setup Options:${NC}"
echo "1. I'll set up DNS manually"
echo "2. Help me set up DuckDNS (free subdomain)"
echo "3. Show me Cloudflare setup instructions"
echo ""
read -p "Choose an option (1-3): " DNS_OPTION

case $DNS_OPTION in
    2)
        echo ""
        echo -e "${BLUE}🦆 DuckDNS Setup:${NC}"
        echo "1. Go to https://www.duckdns.org"
        echo "2. Sign in with GitHub/Reddit/Twitter"
        echo "3. Choose a subdomain (e.g., 'yourname-passkey')"
        echo "4. Set the IP to: $SERVER_IP"
        echo "5. Copy your token from the page"
        echo ""
        echo "Would you like to set up DuckDNS auto-update on the server? (y/n)"
        read -p "> " DUCKDNS_AUTO
        if [ "$DUCKDNS_AUTO" == "y" ]; then
            read -p "Enter your DuckDNS subdomain: " DUCKDNS_DOMAIN
            read -sp "Enter your DuckDNS token: " DUCKDNS_TOKEN
            echo ""
            
            ssh -i ~/.ssh/hetzner_key root@"$SERVER_IP" << DUCK
mkdir -p /root/duckdns
echo "echo url=\"https://www.duckdns.org/update?domains=$DUCKDNS_DOMAIN&token=$DUCKDNS_TOKEN&ip=\" | curl -k -o /root/duckdns/duck.log -K -" > /root/duckdns/duck.sh
chmod 700 /root/duckdns/duck.sh
echo "*/5 * * * * /root/duckdns/duck.sh >/dev/null 2>&1" | crontab -
/root/duckdns/duck.sh
DUCK
            echo -e "${GREEN}✅ DuckDNS auto-update configured${NC}"
            echo "Your domain: https://$DUCKDNS_DOMAIN.duckdns.org"
        fi
        ;;
    3)
        echo ""
        echo -e "${BLUE}☁️  Cloudflare Setup:${NC}"
        echo "1. Log into Cloudflare Dashboard"
        echo "2. Select your domain"
        echo "3. Go to DNS settings"
        echo "4. Add an A record:"
        echo "   - Type: A"
        echo "   - Name: passkey (or your preferred subdomain)"
        echo "   - IPv4 address: $SERVER_IP"
        echo "   - Proxy status: Proxied (orange cloud) for DDoS protection"
        echo "   - TTL: Auto"
        echo "5. Save the record"
        echo ""
        echo "Your domain will be: https://passkey.yourdomain.com"
        ;;
esac

echo ""
echo -e "${GREEN}🎉 Setup complete! Your server is ready for deployment.${NC}"