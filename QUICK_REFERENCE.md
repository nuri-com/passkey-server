# Passkey Server Quick Reference

## Base URL
```
https://passkey.nuri.com
```

## Registration Flow
```
1. GET  /generate-registration-options?username=john_doe
2. Create credential with platform authenticator
3. POST /verify-registration
   Body: {
     "username": "john_doe",
     "challengeKey": "from_step_1",
     "cred": { /* credential response */ }
   }
```

## Authentication Flow
```
1. GET  /generate-authentication-options
2. Get credential from platform authenticator
3. POST /verify-authentication
   Body: {
     "cred": { /* credential response */ }
   }
```

## Key Points
- All binary data must be Base64URL encoded
- RP ID is `nuri.com` for all platforms
- User verification is `preferred` (not required)
- Anonymous users supported (omit username)
- Challenges expire after 60 seconds

## Platform-Specific Notes

### iOS
- Use `ASAuthorizationController`
- For YubiKey: set `userVerificationPreference = .discouraged`

### Android
- Use `CredentialManager` API
- Requires Android 14+ for best support
- Add Play Services FIDO dependency

### Web
- Use `navigator.credentials` API
- Must be served over HTTPS
- Check browser compatibility

## Response Formats

### Success
```json
{
  "verified": true,
  "userId": 123,
  "username": "john_doe"
}
```

### Error
```json
{
  "error": "Error message here"
}
```

## Common Issues

1. **Authenticator not found**
   - Credential wasn't registered on this server
   - Client using wrong credential ID

2. **Challenge not found**
   - Challenge expired (>60 seconds)
   - Wrong challengeKey sent

3. **Origin not allowed**
   - Must use https://nuri.com or https://passkey.nuri.com
   - Check CORS headers

## Testing
Dashboard available at: https://passkey.nuri.com/dashboard.html