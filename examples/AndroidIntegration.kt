// Android Passkey Integration Example
// Requires Android 14+ (API 34+) for best support

package com.example.passkeyintegration

import android.content.Context
import androidx.credentials.*
import androidx.credentials.exceptions.*
import com.google.android.gms.fido.Fido
import com.google.android.gms.fido.fido2.api.common.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.util.Base64

class PasskeyServerIntegration(private val context: Context) {
    private val credentialManager = CredentialManager.create(context)
    private val serverUrl = "https://passkey.nuri.com"
    private var sessionToken: String? = null
    
    // REGISTRATION FLOW
    suspend fun registerNewPasskey(username: String? = null): Result<String> {
        return try {
            // Step 1: Get registration options from server
            val optionsUrl = if (username != null) {
                "$serverUrl/generate-registration-options?username=$username"
            } else {
                "$serverUrl/generate-registration-options"
            }
            
            val optionsResponse = httpGet(optionsUrl)
            val options = JSONObject(optionsResponse)
            
            // Step 2: Create the credential request JSON
            val createCredentialRequest = JSONObject().apply {
                put("rp", options.getJSONObject("rp"))
                put("user", options.getJSONObject("user"))
                put("challenge", options.getString("challenge"))
                put("pubKeyCredParams", options.getJSONArray("pubKeyCredParams"))
                put("timeout", options.getLong("timeout"))
                put("attestation", options.getString("attestation"))
                put("authenticatorSelection", options.getJSONObject("authenticatorSelection"))
            }
            
            // Step 3: Create passkey using Credential Manager
            val createRequest = CreatePublicKeyCredentialRequest(
                requestJson = createCredentialRequest.toString()
            )
            
            val result = credentialManager.createCredential(
                request = createRequest,
                context = context
            ) as CreatePublicKeyCredentialResponse
            
            // Step 4: Parse the response
            val responseJson = JSONObject(result.registrationResponseJson)
            
            // Step 5: Verify with server
            val verifyRequest = JSONObject().apply {
                put("username", username ?: "Anonymous")
                put("challengeKey", options.getString("challengeKey"))
                put("cred", JSONObject().apply {
                    put("id", responseJson.getString("id"))
                    put("rawId", responseJson.getString("rawId"))
                    put("type", responseJson.getString("type"))
                    put("response", responseJson.getJSONObject("response"))
                })
            }
            
            val verifyResponse = httpPost(
                "$serverUrl/verify-registration",
                verifyRequest.toString()
            )
            
            val verifyResult = JSONObject(verifyResponse)
            if (verifyResult.getBoolean("verified")) {
                Result.success("Registration successful for user: ${verifyResult.getString("username")}")
            } else {
                Result.failure(Exception("Registration verification failed"))
            }
            
        } catch (e: CreateCredentialCancellationException) {
            Result.failure(Exception("User cancelled registration"))
        } catch (e: CreateCredentialException) {
            Result.failure(Exception("Registration failed: ${e.message}"))
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
    
    // AUTHENTICATION FLOW
    suspend fun authenticateWithPasskey(): Result<String> {
        return try {
            // Step 1: Get authentication options
            val optionsResponse = httpGet("$serverUrl/generate-authentication-options")
            val options = JSONObject(optionsResponse)
            
            // Step 2: Create authentication request
            val authRequest = JSONObject().apply {
                put("challenge", options.getString("challenge"))
                put("timeout", options.getLong("timeout"))
                put("rpId", options.getString("rpId"))
                put("userVerification", options.getString("userVerification"))
                if (options.has("allowCredentials")) {
                    put("allowCredentials", options.getJSONArray("allowCredentials"))
                }
            }
            
            // Step 3: Get credential
            val getCredentialRequest = GetPublicKeyCredentialOption(
                requestJson = authRequest.toString()
            )
            
            val getRequest = GetCredentialRequest(
                listOf(getCredentialRequest)
            )
            
            val result = credentialManager.getCredential(
                request = getRequest,
                context = context
            )
            
            val credential = result.credential as GetPublicKeyCredentialResponse
            val responseJson = JSONObject(credential.authenticationResponseJson)
            
            // Step 4: Verify with server
            val verifyRequest = JSONObject().apply {
                put("cred", responseJson)
            }
            
            val verifyResponse = httpPost(
                "$serverUrl/verify-authentication",
                verifyRequest.toString()
            )
            
            val authResult = JSONObject(verifyResponse)
            if (authResult.getBoolean("verified")) {
                // Store session token if provided
                if (authResult.has("sessionToken")) {
                    sessionToken = authResult.getString("sessionToken")
                }
                Result.success("Authenticated as: ${authResult.getString("username")}")
            } else {
                Result.failure(Exception("Authentication failed"))
            }
            
        } catch (e: GetCredentialCancellationException) {
            Result.failure(Exception("User cancelled authentication"))
        } catch (e: NoCredentialException) {
            Result.failure(Exception("No passkeys found"))
        } catch (e: GetCredentialException) {
            Result.failure(Exception("Authentication failed: ${e.message}"))
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
    
    // STORE ENCRYPTED DATA
    suspend fun storeUserData(data: Map<String, Any>): Result<Boolean> {
        return try {
            val token = sessionToken ?: return Result.failure(Exception("Not authenticated"))
            
            val request = JSONObject().apply {
                put("data", JSONObject(data))
            }
            
            val response = httpPost(
                "$serverUrl/store-data",
                request.toString(),
                mapOf("Authorization" to "Bearer $token")
            )
            
            val result = JSONObject(response)
            Result.success(result.getBoolean("success"))
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
    
    // RETRIEVE USER DATA
    suspend fun getUserData(): Result<Map<String, Any>> {
        return try {
            val token = sessionToken ?: return Result.failure(Exception("Not authenticated"))
            
            val response = httpGet(
                "$serverUrl/get-data",
                mapOf("Authorization" to "Bearer $token")
            )
            
            val result = JSONObject(response)
            val data = result.getJSONObject("data")
            
            // Convert JSONObject to Map
            val dataMap = mutableMapOf<String, Any>()
            data.keys().forEach { key ->
                dataMap[key] = data.get(key)
            }
            
            Result.success(dataMap)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
    
    // Helper function for HTTP GET requests
    private suspend fun httpGet(
        url: String,
        headers: Map<String, String> = emptyMap()
    ): String = withContext(Dispatchers.IO) {
        val connection = java.net.URL(url).openConnection() as java.net.HttpURLConnection
        connection.requestMethod = "GET"
        headers.forEach { (key, value) ->
            connection.setRequestProperty(key, value)
        }
        connection.inputStream.bufferedReader().use { it.readText() }
    }
    
    // Helper function for HTTP POST requests
    private suspend fun httpPost(
        url: String,
        body: String,
        headers: Map<String, String> = emptyMap()
    ): String = withContext(Dispatchers.IO) {
        val connection = java.net.URL(url).openConnection() as java.net.HttpURLConnection
        connection.requestMethod = "POST"
        connection.setRequestProperty("Content-Type", "application/json")
        headers.forEach { (key, value) ->
            connection.setRequestProperty(key, value)
        }
        connection.doOutput = true
        
        connection.outputStream.use { os ->
            os.write(body.toByteArray())
        }
        
        connection.inputStream.bufferedReader().use { it.readText() }
    }
}

// Usage Example in an Activity or Fragment
class MainActivity : AppCompatActivity() {
    private lateinit var passkeyIntegration: PasskeyServerIntegration
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        passkeyIntegration = PasskeyServerIntegration(this)
    }
    
    fun onRegisterClick() {
        lifecycleScope.launch {
            when (val result = passkeyIntegration.registerNewPasskey("test_user")) {
                is Result.Success -> {
                    Toast.makeText(this@MainActivity, result.value, Toast.LENGTH_SHORT).show()
                }
                is Result.Failure -> {
                    Toast.makeText(this@MainActivity, "Registration failed: ${result.error.message}", Toast.LENGTH_SHORT).show()
                }
            }
        }
    }
    
    fun onAuthenticateClick() {
        lifecycleScope.launch {
            when (val result = passkeyIntegration.authenticateWithPasskey()) {
                is Result.Success -> {
                    Toast.makeText(this@MainActivity, result.value, Toast.LENGTH_SHORT).show()
                    // Now you can store/retrieve user data
                }
                is Result.Failure -> {
                    Toast.makeText(this@MainActivity, "Authentication failed: ${result.error.message}", Toast.LENGTH_SHORT).show()
                }
            }
        }
    }
}