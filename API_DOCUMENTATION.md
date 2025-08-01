# Passkey Server API Documentation

This document describes how to integrate with the Nuri Passkey Server from any client application (Android, iOS, Web, etc.).

## Server Details
- **Base URL**: `https://passkey.nuri.com`
- **RP ID**: `nuri.com`
- **Supported Origins**: `https://passkey.nuri.com`, `https://nuri.com`

## Authentication Flow Overview

1. **Registration**: Create a new passkey for a user
2. **Authentication**: Sign in with an existing passkey
3. **Data Storage**: Store encrypted data associated with the user

## API Endpoints

### 1. Generate Registration Options
Get the challenge and options needed to create a new passkey.

**Endpoint**: `GET /generate-registration-options`

**Query Parameters**:
- `username` (optional): Username for the account. If not provided, creates anonymous user.

**Example Request**:
```bash
# Named user
GET https://passkey.nuri.com/generate-registration-options?username=john_doe

# Anonymous user
GET https://passkey.nuri.com/generate-registration-options
```

**Response**:
```json
{
  "challenge": "uMgkqqp2bLRJZHSqR6D4...",
  "rp": {
    "id": "nuri.com",
    "name": "Nuri Passkey Server"
  },
  "user": {
    "id": "base64url-encoded-user-id",
    "name": "john_doe",
    "displayName": "john_doe"
  },
  "pubKeyCredParams": [
    { "alg": -8, "type": "public-key" },
    { "alg": -7, "type": "public-key" },
    { "alg": -257, "type": "public-key" }
  ],
  "timeout": 60000,
  "attestation": "none",
  "excludeCredentials": [],
  "authenticatorSelection": {
    "residentKey": "required",
    "userVerification": "preferred",
    "requireResidentKey": true
  },
  "extensions": { "credProps": true },
  "challengeKey": "john_doe"  // or "anon_1234567890" for anonymous
}
```

### 2. Verify Registration
Submit the credential created by the authenticator for verification and storage.

**Endpoint**: `POST /verify-registration`

**Headers**:
```
Content-Type: application/json
```

**Request Body**:
```json
{
  "username": "john_doe",  // or "Anonymous" for anonymous users
  "challengeKey": "john_doe",  // from registration options response
  "cred": {
    "id": "base64url-encoded-credential-id",
    "rawId": "base64url-encoded-credential-id",
    "type": "public-key",
    "response": {
      "attestationObject": "base64url-encoded-attestation",
      "clientDataJSON": "base64url-encoded-client-data",
      "transports": ["usb", "nfc", "ble", "internal"]  // optional
    }
  }
}
```

**Response (Success)**:
```json
{
  "verified": true,
  "userId": 123,
  "username": "john_doe"
}
```

**Response (Error)**:
```json
{
  "error": "Challenge not found"
}
```

### 3. Generate Authentication Options
Get the challenge needed to authenticate with an existing passkey.

**Endpoint**: `GET /generate-authentication-options`

**Example Request**:
```bash
GET https://passkey.nuri.com/generate-authentication-options
```

**Response**:
```json
{
  "challenge": "X2JqnWMrEgrRyFq6PRsu3JBP...",
  "timeout": 60000,
  "rpId": "nuri.com",
  "userVerification": "preferred",
  "allowCredentials": []  // Empty array allows any credential
}
```

### 4. Verify Authentication
Submit the signed challenge to authenticate the user.

**Endpoint**: `POST /verify-authentication`

**Headers**:
```
Content-Type: application/json
```

**Request Body**:
```json
{
  "cred": {
    "id": "base64url-encoded-credential-id",
    "rawId": "base64url-encoded-credential-id",
    "type": "public-key",
    "response": {
      "authenticatorData": "base64url-encoded-auth-data",
      "clientDataJSON": "base64url-encoded-client-data",
      "signature": "base64url-encoded-signature",
      "userHandle": "base64url-encoded-user-handle"  // optional
    }
  }
}
```

**Response (Success)**:
```json
{
  "verified": true,
  "userId": 123,
  "username": "john_doe"
}
```

**Response (Error)**:
```json
{
  "error": "Authenticator not found"
}
```

### 5. Store User Data
Store encrypted data associated with the authenticated user.

**Endpoint**: `POST /store-data`

**Headers**:
```
Content-Type: application/json
Authorization: Bearer <session-token>  // Received from verify-authentication
```

**Request Body**:
```json
{
  "data": {
    "encrypted": "your-encrypted-data",
    "anyField": "any-value"
  }
}
```

**Response**:
```json
{
  "success": true
}
```

### 6. Get User Data
Retrieve stored data for the authenticated user.

**Endpoint**: `GET /get-data`

**Headers**:
```
Authorization: Bearer <session-token>  // Received from verify-authentication
```

**Response**:
```json
{
  "data": {
    "encrypted": "your-encrypted-data",
    "anyField": "any-value"
  },
  "lastUpdated": "2025-07-31T10:30:00Z"
}
```

## Android Integration Example

### 1. Add Dependencies (build.gradle)
```gradle
dependencies {
    implementation 'androidx.credentials:credentials:1.3.0'
    implementation 'androidx.credentials:credentials-play-services-auth:1.3.0'
    implementation 'com.google.android.gms:play-services-fido:21.1.0'
}
```

### 2. Registration Flow
```kotlin
class PasskeyManager(private val context: Context) {
    private val credentialManager = CredentialManager.create(context)
    
    suspend fun registerPasskey(username: String? = null) {
        // Step 1: Get registration options from server
        val optionsResponse = api.getRegistrationOptions(username)
        
        // Step 2: Create credential
        val createRequest = CreatePublicKeyCredentialRequest(
            requestJson = buildRegistrationJson(optionsResponse)
        )
        
        try {
            val result = credentialManager.createCredential(
                request = createRequest,
                context = context
            )
            
            // Step 3: Verify with server
            val credential = result as CreatePublicKeyCredentialResponse
            api.verifyRegistration(
                username = username ?: "Anonymous",
                challengeKey = optionsResponse.challengeKey,
                credential = parseCredentialResponse(credential)
            )
        } catch (e: Exception) {
            // Handle errors
        }
    }
    
    private fun buildRegistrationJson(options: RegistrationOptions): String {
        return JSONObject().apply {
            put("challenge", options.challenge)
            put("rp", JSONObject().apply {
                put("name", options.rp.name)
                put("id", options.rp.id)
            })
            put("user", JSONObject().apply {
                put("id", options.user.id)
                put("name", options.user.name)
                put("displayName", options.user.displayName)
            })
            put("pubKeyCredParams", JSONArray().apply {
                options.pubKeyCredParams.forEach { param ->
                    put(JSONObject().apply {
                        put("type", param.type)
                        put("alg", param.alg)
                    })
                }
            })
            put("timeout", options.timeout)
            put("attestation", options.attestation)
            put("authenticatorSelection", JSONObject().apply {
                put("residentKey", options.authenticatorSelection.residentKey)
                put("userVerification", options.authenticatorSelection.userVerification)
            })
        }.toString()
    }
}
```

### 3. Authentication Flow
```kotlin
suspend fun authenticateWithPasskey() {
    // Step 1: Get authentication options
    val optionsResponse = api.getAuthenticationOptions()
    
    // Step 2: Get credential
    val getRequest = GetPublicKeyCredentialOption(
        requestJson = buildAuthenticationJson(optionsResponse)
    )
    
    val getCredRequest = GetCredentialRequest(
        listOf(getRequest)
    )
    
    try {
        val result = credentialManager.getCredential(
            request = getCredRequest,
            context = context
        )
        
        // Step 3: Verify with server
        val credential = result.credential as GetPublicKeyCredentialResponse
        val authResult = api.verifyAuthentication(
            credential = parseAuthCredentialResponse(credential)
        )
        
        // Save session token
        sessionToken = authResult.sessionToken
    } catch (e: Exception) {
        // Handle errors
    }
}
```

## Important Notes

### 1. Base64URL Encoding
All binary data (credential IDs, challenges, etc.) must be encoded using Base64URL format:
- Replace `+` with `-`
- Replace `/` with `_`
- Remove padding `=`

### 2. User Verification
The server accepts both:
- **Platform authenticators** (fingerprint, Face ID): User verification performed
- **Hardware security keys** (YubiKey): User verification optional (touch only)

### 3. Anonymous Users
- Don't provide a username during registration
- Server creates anonymous user with ID like `anon_123456`
- Credential ID becomes the user identifier

### 4. Error Handling
Common errors:
- `400 Bad Request`: Invalid request format
- `404 Not Found`: Challenge expired or credential not found
- `500 Internal Server Error`: Server issue

### 5. Session Management
After successful authentication:
- Server returns a session token
- Include in Authorization header for subsequent requests
- Token expires after inactivity

## Testing

### Test Endpoints
The server includes a web dashboard for testing:
- Registration: `https://passkey.nuri.com/dashboard.html`
- Click "Register Platform Authenticator" or "Register Security Key"

### Debug Mode
For debugging, the server logs:
- Credential IDs being searched
- Available credentials in database
- Encoding formats for comparison

## Security Considerations

1. **HTTPS Required**: WebAuthn only works over secure connections
2. **Origin Validation**: Server validates requests come from allowed origins
3. **Challenge Expiration**: Challenges expire after 60 seconds
4. **Replay Protection**: Each challenge can only be used once

## Support

For issues or questions:
- GitHub: https://github.com/nuri-com/passkey-server
- Server logs: Check PM2 logs for detailed error messages