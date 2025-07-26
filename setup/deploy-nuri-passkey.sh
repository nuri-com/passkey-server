#!/bin/bash

# Special deployment for passkey.nuri.com with nuri.com as RP_ID

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}🚀 Nuri Passkey Server Deployment${NC}"
echo "=================================="
echo ""

# Configuration for nuri.com setup
DOMAIN="passkey.nuri.com"
RPID="nuri.com"  # Parent domain for iOS compatibility
EMAIL="admin@nuri.com"  # Change this to your email
SERVER_IP="116.203.208.144"

echo -e "${BLUE}📋 Configuration:${NC}"
echo "  Domain: $DOMAIN"
echo "  RP ID: $RPID (parent domain for iOS)"
echo "  Server IP: $SERVER_IP"
echo ""

# Check DNS
echo -e "${BLUE}🔍 Checking DNS...${NC}"
DNS_IP=$(dig +short passkey.nuri.com @8.8.8.8 2>/dev/null || echo "")
if [ "$DNS_IP" == "$SERVER_IP" ]; then
    echo -e "${GREEN}✅ DNS is configured correctly!${NC}"
else
    echo -e "${YELLOW}⚠️  DNS not ready yet. Current resolution: $DNS_IP${NC}"
    echo "Please add this DNS record:"
    echo "  Type: A"
    echo "  Name: passkey"
    echo "  Value: $SERVER_IP"
    echo ""
    read -p "Press Enter when DNS is configured..."
fi

# Generate secure passwords
DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
SESSION_SECRET=$(openssl rand -base64 32)

echo -e "${GREEN}✅ Generated secure passwords${NC}"

# Run deployment
./deploy-passkey-server.sh

echo ""
echo -e "${GREEN}🎉 Deployment complete!${NC}"
echo ""
echo "Your passkey server is configured with:"
echo "  URL: https://passkey.nuri.com"
echo "  RP ID: nuri.com"
echo ""
echo "This matches your iOS app's webcredentials:nuri.com configuration!"