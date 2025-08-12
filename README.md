# Passkey Authentication Server

A WebAuthn/Passkey authentication server designed for secure, passwordless authentication with support for encrypted data storage. This server is specifically architected to work as a secure authentication layer for applications that need to protect sensitive data like cryptocurrency wallet seeds.

## Architecture Overview

This server implements a security architecture where:
- **Passkeys** serve as the authentication mechanism (the "lock")
- **AES encryption keys** are stored server-side, protected by passkey authentication
- **Encrypted sensitive data** (e.g., Bitcoin seed phrases) are stored in client-side secure storage (iCloud Keychain)
- The server never has access to decrypt user's sensitive data

### Security Model

```
User → Passkey Authentication → Server returns AES Key → Decrypt local encrypted data
```

This separation ensures that:
1. Server compromise alone cannot decrypt user data
2. Client-side breach alone cannot decrypt without authentication
3. Users can safely backup encrypted data anywhere (QR codes, cloud storage, etc.)

## Table of Contents

1. [Key Features](#key-features)
2. [Prerequisites](#prerequisites)
3. [Server Setup](#server-setup)
4. [API Documentation](#api-documentation)
5. [iOS/Swift Integration Guide](#iosswift-integration-guide)
6. [Wallet Implementation Flow](#wallet-implementation-flow)
7. [Testing](#testing)
8. [Security Considerations](#security-considerations)

## Key Features

- **Passkey Authentication**: WebAuthn-based passwordless authentication
- **Secure Key Storage**: AES encryption keys stored server-side, accessible only after authentication
- **Anonymous User Support**: Users can use the service without providing personal information
- **Multi-Passkey Support**: Users can register multiple passkeys for account recovery
- **Encrypted Data Storage**: Store encrypted blobs (like AES keys) tied to user accounts
- **Dashboard**: Web interface for monitoring users and passkeys
- **Cross-Platform**: Works with iOS, Android, and web clients

## Prerequisites

- Node.js 20+
- PostgreSQL
- Port 3000 available

### For iOS Development
- Xcode 14+
- iOS 16+ device or simulator
- Swift 5.0+
- Understanding of ASAuthorization framework

## Server Setup

### Current Status
The server is already running on this machine at `http://localhost:3000`

### Access Points
- **API**: `http://localhost:3000`
- **Dashboard**: `http://localhost:3000/dashboard`
- **Health Check**: `http://localhost:3000/health`

### Configuration
```env
RP_ID=localhost
RP_NAME=Nuri Passkey Server
ORIGIN=https://localhost
```

## API Documentation

### Authentication Flow

1. **Registration Flow**:
   - GET `/generate-registration-options` → Get WebAuthn options
   - User completes biometric/passkey creation on device
   - POST `/verify-registration` → Verify and store credential

2. **Login Flow**:
   - GET `/generate-authentication-options` → Get challenge
   - User completes biometric/passkey verification
   - POST `/verify-authentication` → Verify and authenticate

### Detailed API Endpoints

#### 1. Generate Registration Options
```http
GET /generate-registration-options?username=john_doe
```

**Query Parameters:**
- `username` (optional): For named users. Omit for anonymous users.

**Response:**
```json
{
  "challenge": "base64url-encoded-challenge",
  "rp": {
    "name": "Nuri Passkey Server",
    "id": "localhost"
  },
  "user": {
    "id": "base64url-encoded-user-id",
    "name": "john_doe",
    "displayName": "john_doe"
  },
  "pubKeyCredParams": [...],
  "timeout": 60000,
  "attestation": "none",
  "excludeCredentials": [],
  "authenticatorSelection": {
    "residentKey": "required",
    "userVerification": "required"
  },
  "challengeKey": "john_doe"
}
```

#### 2. Verify Registration
```http
POST /verify-registration
Content-Type: application/json

{
  "username": "john_doe",
  "challengeKey": "john_doe",
  "cred": {
    "id": "credential-id",
    "rawId": "base64url-encoded-raw-id",
    "type": "public-key",
    "response": {
      "attestationObject": "base64url-encoded",
      "clientDataJSON": "base64url-encoded",
      "transports": ["internal", "hybrid"]
    }
  }
}
```

**Response:**
```json
{
  "verified": true,
  "username": "john_doe",
  "isAnonymous": false
}
```

#### 3. Generate Authentication Options
```http
GET /generate-authentication-options
```

**Response:**
```json
{
  "challenge": "base64url-encoded-challenge",
  "timeout": 60000,
  "rpId": "localhost",
  "allowCredentials": [],
  "userVerification": "required"
}
```

#### 4. Verify Authentication
```http
POST /verify-authentication
Content-Type: application/json

{
  "cred": {
    "id": "credential-id",
    "rawId": "base64url-encoded-raw-id",
    "type": "public-key",
    "response": {
      "authenticatorData": "base64url-encoded",
      "clientDataJSON": "base64url-encoded",
      "signature": "base64url-encoded",
      "userHandle": "base64url-encoded"
    }
  }
}
```

**Response:**
```json
{
  "verified": true,
  "username": "john_doe",
  "isAnonymous": false
}
```

#### 5. Store Encrypted Data (AES Key)
```http
POST /api/users/:username/data
Content-Type: application/json

{
  "encryptedData": {
    "aesKey": "base64-encoded-aes-key"
  },
  "credentialId": "credential-id-for-anonymous"
}
```

**Note**: This endpoint requires prior authentication. The AES key should be generated client-side and stored here for later retrieval.

#### 6. Retrieve Encrypted Data (AES Key)
```http
GET /api/users/:username/data?credentialId=xxx
```

**Returns**:
```json
{
  "username": "john_doe",
  "encryptedData": {
    "aesKey": "base64-encoded-aes-key"
  }
}
```

#### 7. User Query Endpoints
- `GET /api/users/:username/exists` - Check if username exists
- `GET /api/users/:username/passkeys` - List all passkeys for a user

#### 8. Dashboard & Management
- `GET /dashboard` - Web dashboard
- `GET /api/dashboard` - Dashboard API data
- `DELETE /api/users/:username` - Delete user
- `DELETE /api/clear-database` - Clear all data (dev only)

For complete API documentation with request/response examples, see [docs/API.md](docs/API.md)

## iOS/Swift Integration Guide

### Overview
The integration follows this flow:
1. User taps "Passkey" button
2. App attempts authentication
3. If passkey exists → Retrieve AES key → Decrypt local data
4. If no passkey → Create one → Generate AES key → Store on server

### Required Frameworks
- `AuthenticationServices` for passkey operations
- `CryptoKit` for AES encryption
- Standard networking libraries for API calls

### Implementation Steps

1. **Single Button Flow**
   - Call `/generate-authentication-options`
   - Present ASAuthorization UI
   - Handle success/failure appropriately

2. **Data Encoding**
   - All binary data must be base64url encoded
   - Challenges come as base64url, decode for iOS use
   - Encode responses before sending to server

3. **Key Storage Architecture**
   - Generate AES-256 key on first use
   - Store AES key on server via `/api/users/{username}/data`
   - Store encrypted Bitcoin seed in iCloud Keychain
   - Never store AES key and encrypted data together

## Wallet Implementation Flow

### Initial Setup (New User)
1. **User opens app** → Shows welcome screen with single "Passkey" button
2. **Tap Passkey** → Call `/generate-authentication-options`
3. **No passkey found** → System shows "Create Passkey" option
4. **Create passkey** → Call `/generate-registration-options` and `/verify-registration`
5. **Generate AES key** → Create random 256-bit key client-side
6. **Store AES key** → POST to `/api/users/{username}/data`
7. **Encrypt seed** → Use AES key to encrypt Bitcoin seed
8. **Store encrypted seed** → Save to iCloud Keychain
9. **Success** → Navigate to main wallet screen

### Daily Use (Returning User)
1. **User opens app** → Shows welcome screen
2. **Tap Passkey** → Call `/generate-authentication-options`
3. **Select passkey** → iOS shows available passkeys
4. **Authenticate** → Call `/verify-authentication`
5. **Fetch AES key** → GET from `/api/users/{username}/data`
6. **Retrieve encrypted seed** → From iCloud Keychain
7. **Decrypt seed** → Use AES key in memory
8. **Success** → Navigate to main wallet screen

### Recovery Options
1. **From iCloud**: Authenticate → Get AES key from server → Decrypt
2. **From QR Code**: Scan encrypted seed → Authenticate → Get AES key → Decrypt
3. **New Device**: Sign in with Apple ID → Passkey syncs → Normal flow

### Security Architecture

```
┌─────────────┐     ┌──────────────┐     ┌────────────────┐
│   Passkey   │────▶│    Server    │────▶│   AES Key      │
│   (Lock)    │     │   (Stores)   │     │  (Plain text)  │
└─────────────┘     └──────────────┘     └────────────────┘
                            │
                            ▼
┌─────────────┐     ┌──────────────┐     ┌────────────────┐
│   iCloud    │────▶│  Encrypted   │◀────│   Bitcoin      │
│  Keychain   │     │    Seed      │     │     Seed       │
└─────────────┘     └──────────────┘     └────────────────┘
```

**Key Points**:
- Passkey authenticates user
- Server returns AES key (only after auth)
- AES key decrypts seed stored in iCloud
- Server never sees Bitcoin seed
- Encrypted seed can be safely backed up anywhere

## Testing

### Local Testing
- Server running at: `http://localhost:3000`
- For iOS Simulator: Use `http://localhost:3000`
- For physical device: Use machine's IP address (e.g., `http://192.168.1.x:3000`)

### Test Endpoints
```bash
# Health check
curl http://localhost:3000/health

# View dashboard
open http://localhost:3000/dashboard
```

## Security Considerations

### Architecture Benefits
1. **Separation of Concerns**: AES key and encrypted data stored separately
2. **Zero-Knowledge**: Server cannot decrypt user's Bitcoin seeds
3. **Multi-Factor**: Requires both passkey auth and access to encrypted data
4. **Backup Friendly**: Encrypted seeds can be stored anywhere safely

### Best Practices
1. **Never store** AES key and encrypted seed in the same location
2. **Always generate** AES keys using cryptographically secure methods
3. **Clear memory** after using sensitive data
4. **Use AES-256-GCM** for authenticated encryption
5. **Implement rate limiting** for production use

### What This Protects Against
- **Server breach**: Attacker only gets AES keys, no encrypted data
- **iCloud breach**: Attacker only gets encrypted data, no keys
- **Lost device**: Passkey + iCloud sync enables recovery
- **Phishing**: Passkeys are domain-bound and cannot be phished

### Production Considerations
1. Use HTTPS with valid certificates
2. Implement proper session management
3. Add rate limiting and DDoS protection
4. Regular security audits
5. Secure database backups
6. Monitor for suspicious authentication patterns

## Deployment

See [DEPLOYMENT.md](DEPLOYMENT.md) for detailed production deployment instructions.

### Quick Start
1. Clone this repository
2. Copy `.env.example` to `.env` and configure
3. Install dependencies: `npm install`
4. Run locally: `npm start`

### Production Deployment
- **Deployed to**: Hetzner Cloud (CPX11)
- **Live at**: https://passkey.nuri.com
- **Architecture**: Node.js + PostgreSQL + Nginx
- **SSL**: Let's Encrypt

## Support

For issues with the server:
- Check server health: `curl http://localhost:3000/health`
- View dashboard: `http://localhost:3000/dashboard`
- Production logs: `pm2 logs passkey-server`
