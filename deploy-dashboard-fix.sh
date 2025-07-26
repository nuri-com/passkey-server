#!/bin/bash

# Quick deployment script for dashboard fix
echo "🚀 Deploying dashboard fix to passkey.nuri.com"
echo "==========================================="

# Try different SSH keys and ports
SSH_KEYS=(
    "~/.ssh/hetzner_short_key"
    "~/.ssh/hetzner_rsa_key" 
    "~/.ssh/hetzner_key"
    "~/.ssh/id_rsa"
)

SSH_PORTS=(22 2222 2022)
SERVER_IP="116.203.208.144"

echo "Trying to connect to server..."

for key in "${SSH_KEYS[@]}"; do
    if [ -f "$key" ]; then
        for port in "${SSH_PORTS[@]}"; do
            echo "Trying $key on port $port..."
            if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i "$key" -p "$port" root@$SERVER_IP "echo 'Connected!'" 2>/dev/null; then
                echo "✅ Connected with $key on port $port"
                echo "Deploying dashboard fix..."
                
                # Pull latest changes
                ssh -i "$key" -p "$port" root@$SERVER_IP "cd /var/www/passkey-server && git pull origin main && echo 'Dashboard updated!'"
                
                # Restart PM2 if needed
                ssh -i "$key" -p "$port" root@$SERVER_IP "pm2 restart passkey-server"
                
                echo "✅ Deployment complete!"
                echo "Visit https://passkey.nuri.com/dashboard to test"
                exit 0
            fi
        done
    fi
done

echo ""
echo "❌ Could not connect via SSH. Here's what you can do:"
echo ""
echo "Option 1: If you have SSH access, run these commands:"
echo "  ssh root@$SERVER_IP"
echo "  cd /var/www/passkey-server"
echo "  git pull origin main"
echo "  pm2 restart passkey-server"
echo ""
echo "Option 2: The fix is already in GitHub. It will be applied next time you deploy."
echo ""
echo "The dashboard fix changes API_BASE from 'https://localhost' to window.location.origin"
echo "This allows it to work on any domain automatically."