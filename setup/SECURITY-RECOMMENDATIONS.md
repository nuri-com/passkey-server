# 🔐 Critical Security Recommendations for Passkey Server Deployment

## ⚠️ DO NOT USE the provided scripts as-is!

### Problems with Current Scripts:

1. **Wrong Server**: `setup-production-server.sh` creates a completely different server with in-memory storage instead of your secure PostgreSQL-based server

2. **Security Issues**:
   - Database passwords visible in bash history
   - SSH open to entire internet (0.0.0.0/0)
   - No intrusion detection (fail2ban)
   - No automated security updates
   - No backup strategy
   - No rate limiting

3. **Version Mismatches**:
   - Uses Node.js 18 (you need 20+)
   - Wrong @simplewebauthn/server version
   - References non-existent files

## ✅ Production Deployment Checklist

### 1. Server Selection
- CPX11 (€4.15/month) is fine for starting
- Enable Hetzner backups (€0.83/month) - CRITICAL
- Choose location close to users

### 2. Initial Security
```bash
# IMMEDIATELY after server creation:
# 1. Change root password
# 2. Create non-root user
# 3. Setup SSH key authentication
# 4. Disable password authentication
# 5. Configure firewall
```

### 3. Use the Secure Script
Use `secure-production-setup.sh` which:
- ✅ Deploys YOUR actual server (not a dummy)
- ✅ Uses Node.js 20
- ✅ Implements security best practices
- ✅ Sets up automated backups
- ✅ Configures fail2ban
- ✅ Restricts SSH access

### 4. Environment Variables
Your server needs:
```env
DATABASE_URL=postgresql://...
RP_ID=your-domain.com
RP_NAME=Nuri Passkey Server  
ORIGIN=https://your-domain.com
SESSION_SECRET=<random-secret>
```

### 5. DNS Setup
- Use Cloudflare for DDoS protection
- Enable "Proxy" in Cloudflare
- Set up rate limiting rules

### 6. Monitoring
- Setup uptime monitoring (UptimeRobot, free)
- Configure alerts for high CPU/memory
- Monitor failed login attempts

### 7. Backup Strategy
- Daily automated PostgreSQL backups
- Store backups off-server (Hetzner Storage Box)
- Test restore procedure regularly

### 8. Security Headers
Nginx should include:
```nginx
add_header Strict-Transport-Security "max-age=31536000" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header Content-Security-Policy "default-src 'self';" always;
```

### 9. Rate Limiting
Add to Nginx:
```nginx
limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
limit_req zone=api burst=20 nodelay;
```

### 10. Post-Deployment
1. Run security audit: `npm audit`
2. Check SSL: https://www.ssllabs.com/ssltest/
3. Test all endpoints
4. Verify backup script works
5. Document recovery procedure

## 🚨 Critical: Before Going Live

1. **Change ALL default passwords**
2. **Enable 2FA on Hetzner account**
3. **Test failover/recovery**
4. **Have incident response plan**
5. **Keep server updated weekly**

## 📱 iOS App Configuration

After deployment, update your Swift app:
```swift
private var baseURL: String {
    return "https://your-actual-domain.com"  // NOT localhost
}
```

## 🆘 If Something Goes Wrong

1. Check logs: `pm2 logs passkey-server`
2. Check Nginx: `nginx -t`
3. Check PostgreSQL: `systemctl status postgresql`
4. Check firewall: `ufw status`
5. Contact Hetzner support if server issue

## 💡 Final Recommendations

1. **Start with staging environment** first
2. **Test everything** before switching iOS app
3. **Keep credentials in password manager**
4. **Regular security updates** (weekly)
5. **Monitor for suspicious activity**

Remember: Your server stores encryption keys for Bitcoin wallets. Security is paramount!