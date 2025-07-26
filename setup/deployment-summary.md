# 🎉 Passkey Server Deployment Complete!

## Server Details

- **URL**: https://passkey.nuri.com
- **IP**: 116.203.208.144
- **Server ID**: 105267239
- **Type**: Hetzner CPX11 (2 vCPU, 2GB RAM)
- **Location**: Nuremberg, Germany
- **Monthly Cost**: €4.15

## Configuration

```javascript
// WebAuthn Configuration
RP_ID = "nuri.com"          // Parent domain for iOS compatibility
RP_NAME = "Nuri Wallet"
ORIGIN = "https://passkey.nuri.com"
```

## Endpoints

- **Health Check**: https://passkey.nuri.com/health ✅
- **Dashboard**: https://passkey.nuri.com/dashboard
- **Registration Options**: https://passkey.nuri.com/generate-registration-options
- **Authentication Options**: https://passkey.nuri.com/generate-authentication-options

## iOS App Configuration

Your iOS app with `webcredentials:nuri.com` will work perfectly with this setup because:
- The server identifies as `nuri.com` (RP_ID)
- But runs at `passkey.nuri.com` (subdomain)
- This matches Apple's requirements for associated domains

## Security Features Enabled

✅ SSL Certificate (Let's Encrypt)
✅ Firewall configured (UFW)
✅ Fail2ban active
✅ Rate limiting on Nginx
✅ Automated daily backups (3 AM)
✅ Health monitoring with auto-restart
✅ Security headers configured

## Management

### SSH Access
```bash
ssh -i ~/.ssh/hetzner_short_key root@116.203.208.144
```

### View Logs
```bash
ssh -i ~/.ssh/hetzner_short_key root@116.203.208.144 "pm2 logs passkey-server"
```

### Restart Server
```bash
ssh -i ~/.ssh/hetzner_short_key root@116.203.208.144 "pm2 restart passkey-server"
```

### Check Status
```bash
ssh -i ~/.ssh/hetzner_short_key root@116.203.208.144 "pm2 status"
```

## Next Steps

1. **Create a non-root user** for better security
2. **Test with your iOS app** - it should work immediately
3. **Set up monitoring** (e.g., UptimeRobot)
4. **Enable Hetzner backups** for €0.83/month extra

## Important Files on Server

- App Location: `/var/www/passkey-server/`
- Environment: `/var/www/passkey-server/.env`
- Logs: `/var/log/pm2/`
- Backups: `/home/passkey/backups/`

## Deployment Time

Total deployment time: ~8 minutes
- Server creation: 2 minutes
- Software installation: 4 minutes
- Configuration & SSL: 2 minutes

Your passkey server is now live and ready for your iOS app!