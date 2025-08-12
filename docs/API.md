# Passkey Server API Documentation

## Table of Contents
- [Authentication Endpoints](#authentication-endpoints)
- [User Management Endpoints](#user-management-endpoints)
- [Data Storage Endpoints](#data-storage-endpoints)
- [Administrative Endpoints](#administrative-endpoints)

## Authentication Endpoints

### Generate Registration Options
Generate WebAuthn registration options for creating a new passkey.

```http
GET /generate-registration-options?username={username}
```

**Query Parameters:**
- `username` (optional): Username for the account. If omitted, creates an anonymous user.

**Response:** WebAuthn registration options object

---

### Verify Registration
Verify and store a newly created passkey credential.

```http
POST /verify-registration
Content-Type: application/json
```

**Request Body:**
```json
{
  "username": "user@example.com",
  "challengeKey": "challenge-key",
  "cred": {
    "id": "credential-id",
    "rawId": "base64url-encoded",
    "type": "public-key",
    "response": {
      "attestationObject": "base64url-encoded",
      "clientDataJSON": "base64url-encoded"
    }
  }
}
```

**Response:**
```json
{
  "verified": true,
  "username": "user@example.com",
  "isAnonymous": false
}
```

---

### Generate Authentication Options
Generate WebAuthn authentication challenge for passkey login.

```http
GET /generate-authentication-options
```

**Response:** WebAuthn authentication options object

---

### Verify Authentication
Verify passkey authentication and log in user.

```http
POST /verify-authentication
Content-Type: application/json
```

**Request Body:**
```json
{
  "cred": {
    "id": "credential-id",
    "rawId": "base64url-encoded",
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
  "username": "user@example.com",
  "isAnonymous": false
}
```

## User Management Endpoints

### Check User Existence
Check if a username is already registered in the system.

```http
GET /api/users/{username}/exists
```

**Parameters:**
- `username` (path): The username to check (URL-encoded if contains special characters)

**Response:**
```json
{
  "exists": true
}
```

**Example:**
```bash
curl "https://passkey.nuri.com/api/users/satoshi%40gmx.com/exists"
# Response: {"exists": true}
```

---

### List User Passkeys
Retrieve all passkeys registered for a specific user.

```http
GET /api/users/{username}/passkeys
```

**Parameters:**
- `username` (path): The username whose passkeys to retrieve (URL-encoded if contains special characters)

**Response:**
```json
{
  "passkeys": [
    {
      "credentialId": "QCM6FGF8caNNwzpo1ShXzbrAUx8",
      "deviceName": "Platform Authenticator",
      "lastUsed": "2025-08-12T10:30:00Z",
      "createdAt": "2025-08-10T14:20:00Z"
    },
    {
      "credentialId": "Myuswwcc5e3d-DaQJAPQSV-K8N9W1nrP...",
      "deviceName": "Security Key",
      "lastUsed": "2025-08-11T09:15:00Z",
      "createdAt": "2025-08-09T11:00:00Z"
    }
  ]
}
```

**Error Responses:**
- `404 Not Found`: User does not exist
  ```json
  {
    "error": "User not found"
  }
  ```
- `500 Internal Server Error`: Database or server error

**Device Name Logic:**
The `deviceName` field is determined by:
1. Stored device name (if available)
2. Transport type analysis:
   - `internal` → "Platform Authenticator" (Face ID, Touch ID, Windows Hello)
   - `usb` → "Security Key" (YubiKey, etc.)
   - `ble` or `nfc` → "Mobile Device"
   - Default → "Unknown Device"

**Example:**
```bash
curl "https://passkey.nuri.com/api/users/satoshi%40gmx.com/passkeys"
# Response: {"passkeys": [...]}
```

---

### Delete User
Delete a user and all associated passkeys.

```http
DELETE /api/users/{username}
```

**Parameters:**
- `username` (path): The username to delete

**Response:**
```json
{
  "message": "User deleted successfully"
}
```

## Data Storage Endpoints

### Store Encrypted Data
Store encrypted data (like AES keys) for a user.

```http
POST /api/users/{identifier}/data
Content-Type: application/json
```

**Parameters:**
- `identifier` (path): Username or credential ID for anonymous users

**Request Body:**
```json
{
  "encryptedData": {
    "aesKey": "base64-encoded-key",
    "customField": "any-encrypted-data"
  },
  "credentialId": "credential-id-for-anonymous"
}
```

**Note:** Requires prior authentication

---

### Retrieve Encrypted Data
Retrieve stored encrypted data for a user.

```http
GET /api/users/{identifier}/data?credentialId={credentialId}
```

**Parameters:**
- `identifier` (path): Username or credential ID
- `credentialId` (query, optional): For anonymous users

**Response:**
```json
{
  "username": "user@example.com",
  "encryptedData": {
    "aesKey": "base64-encoded-key"
  }
}
```

---

### Store Seed Backup
Store an encrypted seed backup for a user.

```http
POST /api/users/{username}/seed-backup
Content-Type: application/json
```

**Request Body:**
```json
{
  "encryptedSeed": "encrypted-seed-data",
  "authProof": "authentication-proof",
  "keyDerivationParams": {
    "salt": "base64-salt",
    "iterations": 100000
  }
}
```

## Administrative Endpoints

### Dashboard
Web-based dashboard for monitoring users and passkeys.

```http
GET /dashboard
```

Returns HTML dashboard interface.

---

### Dashboard API
Get dashboard data in JSON format.

```http
GET /api/dashboard
```

**Response:**
```json
{
  "totalUsers": 42,
  "totalPasskeys": 51,
  "hardwareKeys": 47,
  "platformKeys": 4,
  "users": [
    {
      "id": 1,
      "username": "user@example.com",
      "created_at": "2025-08-01T10:00:00Z",
      "authenticator_count": "2",
      "authenticators": [...]
    }
  ]
}
```

---

### Activity Logs
Retrieve server activity logs.

```http
GET /api/activity-logs
```

---

### Activity Statistics
Get aggregated activity statistics.

```http
GET /api/activity-stats
```

---

### Health Check
Check if the server is running and healthy.

```http
GET /health
```

**Response:**
```json
{
  "status": "ok",
  "service": "passkey-server"
}
```

---

### Clear Database (Development Only)
Clear all data from the database.

```http
DELETE /api/clear-database
```

**Warning:** This endpoint should be disabled in production!

## Error Handling

All endpoints follow consistent error response format:

```json
{
  "error": "Error message description"
}
```

Common HTTP status codes:
- `200 OK`: Successful operation
- `400 Bad Request`: Invalid request parameters
- `404 Not Found`: Resource not found
- `500 Internal Server Error`: Server error

## Rate Limiting

Production deployments should implement rate limiting:
- Authentication attempts: 5 per minute per IP
- Registration attempts: 3 per hour per IP
- API calls: 100 per minute per authenticated user

## CORS Configuration

The server supports CORS for cross-origin requests. Configure allowed origins in the environment variables.

## Security Notes

1. **Always use HTTPS** in production
2. **URL-encode special characters** in usernames (e.g., `@` → `%40`)
3. **Implement rate limiting** to prevent abuse
4. **Monitor authentication patterns** for suspicious activity
5. **Regular security audits** of the codebase
6. **Secure database backups** with encryption