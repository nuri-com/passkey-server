# iOS/Swift Integration Guide for Passkey Server

## Overview

This guide provides complete integration instructions for iOS developers to connect to the passkey server using Swift and the AuthenticationServices framework.

## Server Configuration

- **Base URL**: `https://passkey.nuri.com`
- **RP ID**: `nuri.com` (parent domain - critical for iOS)
- **Origin**: iOS sends `https://nuri.com` (not the subdomain)
- **Endpoints**:
  - Registration: `POST /generate-registration-options`
  - Verify Registration: `POST /verify-registration`
  - Authentication: `GET /generate-authentication-options`
  - Verify Authentication: `POST /verify-authentication`

> **Important**: The server accepts origins from both `https://passkey.nuri.com` (web) and `https://nuri.com` (iOS) to support both platforms.

## Required Setup

### 1. Associated Domains Entitlement

Add to your app's entitlements:
```xml
<key>com.apple.developer.associated-domains</key>
<array>
    <string>webcredentials:nuri.com</string>
</array>
```

### 2. Import Required Frameworks

```swift
import AuthenticationServices
import CryptoKit
```

## API Request/Response Formats

### Registration Flow

#### Step 1: Get Registration Options

**Request:**
```
GET https://passkey.nuri.com/generate-registration-options?username=john_doe
```

For anonymous users, omit the username parameter.

**Response:**
```json
{
    "challenge": "base64url-encoded-challenge",
    "rp": {
        "name": "Nuri Wallet",
        "id": "nuri.com"
    },
    "user": {
        "id": "base64url-encoded-user-id",
        "name": "john_doe",
        "displayName": "john_doe"
    },
    "pubKeyCredParams": [
        {"alg": -7, "type": "public-key"},
        {"alg": -257, "type": "public-key"}
    ],
    "timeout": 60000,
    "attestation": "none",
    "authenticatorSelection": {
        "residentKey": "required",
        "userVerification": "required"
    },
    "challengeKey": "john_doe"
}
```

#### Step 2: Create Credential (iOS)

```swift
// Convert challenge from base64url to Data
let challengeData = Data(base64URLEncoded: options.challenge)!

// Create credential
let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
    relyingPartyIdentifier: "nuri.com"
)

let request = provider.createCredentialRegistrationRequest(
    challenge: challengeData,
    name: options.user.name,
    userID: Data(base64URLEncoded: options.user.id)!
)

// Set options
request.userVerificationPreference = .required
```

#### Step 3: Send Registration to Server

**Request:**
```
POST https://passkey.nuri.com/verify-registration
Content-Type: application/json
```

**Body:**
```json
{
    "username": "john_doe",
    "challengeKey": "john_doe",
    "cred": {
        "id": "base64url-credential-id",
        "rawId": "base64url-credential-id",
        "type": "public-key",
        "response": {
            "clientDataJSON": "base64url-encoded",
            "attestationObject": "base64url-encoded",
            "transports": ["internal"]
        }
    }
}
```

### Authentication Flow

#### Step 1: Get Authentication Options

**Request:**
```
GET https://passkey.nuri.com/generate-authentication-options
```

**Response:**
```json
{
    "challenge": "base64url-encoded-challenge",
    "timeout": 60000,
    "rpId": "nuri.com",
    "allowCredentials": [],
    "userVerification": "required"
}
```

#### Step 2: Authenticate (iOS)

```swift
let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
    relyingPartyIdentifier: "nuri.com"
)

let request = provider.createCredentialAssertionRequest(
    challenge: Data(base64URLEncoded: options.challenge)!
)
```

#### Step 3: Verify Authentication

**Request:**
```
POST https://passkey.nuri.com/verify-authentication
Content-Type: application/json
```

**Body:**
```json
{
    "cred": {
        "id": "base64url-credential-id",
        "rawId": "base64url-credential-id",
        "type": "public-key",
        "response": {
            "clientDataJSON": "base64url-encoded",
            "authenticatorData": "base64url-encoded",
            "signature": "base64url-encoded",
            "userHandle": "base64url-encoded-user-id"
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

## Complete Swift Example

```swift
import AuthenticationServices

class PasskeyService: NSObject {
    let baseURL = "https://passkey.nuri.com"
    
    // MARK: - Registration
    
    func register(username: String?) async throws {
        // 1. Get registration options
        let optionsURL = username != nil 
            ? "\(baseURL)/generate-registration-options?username=\(username!)"
            : "\(baseURL)/generate-registration-options"
            
        let (data, _) = try await URLSession.shared.data(from: URL(string: optionsURL)!)
        let options = try JSONDecoder().decode(RegistrationOptions.self, from: data)
        
        // 2. Create credential
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: "nuri.com"
        )
        
        let request = provider.createCredentialRegistrationRequest(
            challenge: Data(base64URLEncoded: options.challenge)!,
            name: options.user.name,
            userID: Data(base64URLEncoded: options.user.id)!
        )
        
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        
        // ... handle delegate callbacks ...
        
        // 3. Send to server
        let credential = // ... from delegate
        let verifyURL = URL(string: "\(baseURL)/verify-registration")!
        
        let body = [
            "username": username ?? "",
            "challengeKey": options.challengeKey,
            "cred": [
                "id": credential.credentialID.base64URLEncodedString(),
                "rawId": credential.credentialID.base64URLEncodedString(),
                "type": "public-key",
                "response": [
                    "clientDataJSON": credential.rawClientDataJSON.base64URLEncodedString(),
                    "attestationObject": credential.rawAttestationObject!.base64URLEncodedString(),
                    "transports": ["internal"]
                ]
            ]
        ]
        
        var request = URLRequest(url: verifyURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (responseData, _) = try await URLSession.shared.data(for: request)
        // Handle response
    }
    
    // MARK: - Authentication
    
    func authenticate() async throws -> (username: String, isAnonymous: Bool) {
        // 1. Get options
        let optionsURL = URL(string: "\(baseURL)/generate-authentication-options")!
        let (data, _) = try await URLSession.shared.data(from: optionsURL)
        let options = try JSONDecoder().decode(AuthenticationOptions.self, from: data)
        
        // 2. Authenticate
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: "nuri.com"
        )
        
        let request = provider.createCredentialAssertionRequest(
            challenge: Data(base64URLEncoded: options.challenge)!
        )
        
        // ... handle authentication ...
        
        // 3. Verify
        let credential = // ... from delegate
        let verifyURL = URL(string: "\(baseURL)/verify-authentication")!
        
        let body = [
            "cred": [
                "id": credential.credentialID.base64URLEncodedString(),
                "rawId": credential.credentialID.base64URLEncodedString(),
                "type": "public-key",
                "response": [
                    "clientDataJSON": credential.rawClientDataJSON.base64URLEncodedString(),
                    "authenticatorData": credential.rawAuthenticatorData.base64URLEncodedString(),
                    "signature": credential.signature.base64URLEncodedString(),
                    "userHandle": credential.userID?.base64URLEncodedString() ?? ""
                ]
            ]
        ]
        
        var request = URLRequest(url: verifyURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (responseData, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(AuthResponse.self, from: responseData)
        
        return (response.username, response.isAnonymous)
    }
}

// MARK: - Data Extensions

extension Data {
    init?(base64URLEncoded: String) {
        let base64 = base64URLEncoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        let padded = base64.padding(
            toLength: ((base64.count + 3) / 4) * 4,
            withPad: "=",
            startingAt: 0
        )
        
        self.init(base64Encoded: padded)
    }
    
    func base64URLEncodedString() -> String {
        return self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
```

## Common Issues and Solutions

### 1. 500 Error: "The first argument must be of type string"

**Cause**: The credential ID is not being sent correctly.

**Solution**: Ensure you're sending both `id` and `rawId` fields:
```json
{
    "cred": {
        "id": "credential-id-base64url",
        "rawId": "same-credential-id-base64url",
        // ... rest of credential
    }
}
```

### 2. RP ID Mismatch

**Cause**: Using subdomain instead of parent domain.

**Solution**: Always use `nuri.com` as the relying party identifier, not `passkey.nuri.com`.

### 3. Challenge Expired

**Cause**: Taking too long between getting options and sending verification.

**Solution**: Complete the flow within 60 seconds.

### 4. User Not Found

**Cause**: For authentication, the credential doesn't exist on the server.

**Solution**: Ensure registration completed successfully first.

## Testing

1. **Test Registration First**: Always test registration before authentication
2. **Check Console Logs**: The server logs detailed information
3. **Verify Domain Setup**: Ensure `webcredentials:nuri.com` is in your entitlements
4. **Use Real Device**: Passkeys work best on physical devices

## Support

For debugging, check the server dashboard at:
https://passkey.nuri.com/dashboard

The dashboard shows real-time logs and registered users.