# Passkey Server - Important Information for Claude

## Server Details
- **Server IP**: 116.203.208.144
- **Domain**: https://passkey.nuri.com
- **RP_ID**: nuri.com (parent domain for iOS compatibility)
- **Provider**: Hetzner Cloud
- **Location**: Germany

## SSH Access
- **SSH Key**: `~/.ssh/hetzner_short_key`
- **SSH Command**: `ssh -i ~/.ssh/hetzner_short_key root@116.203.208.144`
- **Alternative Keys**: 
  - `~/.ssh/hetzner_rsa_key`
  - `~/.ssh/hetzner_key`

## Application Details
- **Directory**: `/var/www/passkey-server`
- **Process Manager**: PM2
- **Process Name**: passkey-server
- **Web Server**: Nginx
- **Database**: PostgreSQL

## Common Commands
```bash
# SSH to server
ssh -i ~/.ssh/hetzner_short_key root@116.203.208.144

# View logs
pm2 logs passkey-server

# Restart server
pm2 restart passkey-server

# Pull updates from GitHub
cd /var/www/passkey-server && git pull origin main

# Check status
pm2 status
```

## Hetzner Cloud CLI
- **Installed**: Yes (at `/opt/homebrew/bin/hcloud`)
- **API Token**: gccoW05Jpq5cJrrZtRrKDxDzcrYFkSj7XQREN3DeqVXsFYz5QPESt4FX3zD3QG9i
- **Server Name**: passkey-server-20250726-164012
- **Server ID**: 105267239
- **Usage**: Can access server console, reset SSH, check status
- **Commands**:
  ```bash
  # Set token
  export HCLOUD_TOKEN="gccoW05Jpq5cJrrZtRrKDxDzcrYFkSj7XQREN3DeqVXsFYz5QPESt4FX3zD3QG9i"
  
  # List servers
  hcloud server list
  
  # Access console
  hcloud server request-console passkey-server-20250726-164012
  
  # SSH (when working)
  hcloud server ssh passkey-server-20250726-164012
  ```

## SSH Keys
- **Primary Key**: `~/.ssh/passkey-server-key` (saved from user)
- **Alternative Keys**: 
  - `~/.ssh/hetzner_short_key`
  - `~/.ssh/hetzner_rsa_key`
  - `~/.ssh/hetzner_key`

## Current Issue (July 26, 2025)
- SSH port 22 is showing "Connection refused"
- This might indicate:
  1. SSH service is down
  2. Firewall rules changed
  3. SSH port was changed for security
  4. IP-based restrictions were added
- **Solution**: Use Hetzner CLI to access console or reset SSH

## GitHub Repository
- **URL**: https://github.com/nuri-com/passkey-server
- **Main Branch**: main

## Latest Changes
- Fixed dashboard API_BASE to use `window.location.origin` instead of hardcoded `https://localhost`
- This fix has been pushed to GitHub but needs to be deployed to the server

## Deployment Process
1. SSH to server
2. Navigate to `/var/www/passkey-server`
3. Pull latest changes: `git pull origin main`
4. Restart PM2: `pm2 restart passkey-server`