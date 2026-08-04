package com.echo.dictation.data.ai

import android.util.Log
import com.echo.dictation.domain.ai.AIProvider
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * AWS Bedrock AI provider using the Bedrock Converse API with AWS SigV4 signing.
 *
 * The API key field in Settings stores credentials as "ACCESS_KEY_ID:SECRET_ACCESS_KEY[:SESSION_TOKEN]".
 * The base URL field stores the region endpoint, e.g.:
 *   https://bedrock-runtime.us-east-1.amazonaws.com
 *
 * Supported model IDs (examples):
 *   anthropic.claude-3-5-sonnet-20241022-v2:0
 *   anthropic.claude-3-7-sonnet-20250219-v1:0
 *   amazon.nova-lite-v1:0
 *   amazon.nova-pro-v1:0
 *   meta.llama3-3-70b-instruct-v1:0
 */
class BedrockAIProvider(
    /** Raw credential string: "ACCESS_KEY_ID:SECRET_ACCESS_KEY" or "ACCESS_KEY_ID:SECRET_ACCESS_KEY:SESSION_TOKEN" */
    private val credentialsRaw: String,
    private val model: String,
    private val httpClient: OkHttpClient,
) : AIProvider {

    override val id: String = "bedrock"
    override val name: String = "AWS Bedrock"
    override val defaultModel: String = model

    private val credentials: Triple<String, String, String?> by lazy {
        val parts = credentialsRaw.split(":")
        Triple(
            parts.getOrElse(0) { "" },
            parts.getOrElse(1) { "" },
            parts.getOrNull(2),
        )
    }

    override suspend fun generateCompletion(
        systemPrompt: String?,
        userPrompt: String,
        modelOverride: String?
    ): Result<String> = runCatching {
            val (accessKeyId, secretKey, sessionToken) = credentials
            check(accessKeyId.isNotBlank() && secretKey.isNotBlank()) {
                "AWS Bedrock credentials are not configured. " +
                "Set them as 'ACCESS_KEY_ID:SECRET_ACCESS_KEY' in the API Key field."
            }

            val targetModel = modelOverride?.takeIf { it.isNotBlank() } ?: defaultModel
            val region = "us-east-1"

            val bodyObj = JSONObject()

            if (!systemPrompt.isNullOrBlank()) {
                bodyObj.put(
                    "system",
                    JSONArray().put(JSONObject().put("text", systemPrompt))
                )
            }

            bodyObj.put(
                "messages",
                JSONArray().put(
                    JSONObject()
                        .put("role", "user")
                        .put("content", JSONArray().put(JSONObject().put("text", userPrompt)))
                )
            )

            bodyObj.put(
                "inferenceConfig",
                JSONObject()
                    .put("maxTokens", 4096)
                    .put("temperature", 0.2f)
            )

            val bodyString = bodyObj.toString()
            val url = "https://bedrock-runtime.$region.amazonaws.com/model/${
                java.net.URLEncoder.encode(targetModel, "UTF-8").replace("+", "%20")
            }/converse"

            val request = buildSignedRequest(
                url          = url,
                bodyString   = bodyString,
                region       = region,
                accessKeyId  = accessKeyId,
                secretKey    = secretKey,
                sessionToken = sessionToken,
            )

            val responseBody = executeAsync(request)

            val content = JSONObject(responseBody)
                .getJSONObject("output")
                .getJSONObject("message")
                .getJSONArray("content")
                .getJSONObject(0)
                .getString("text")
                .trim()

            Log.d(TAG, "Bedrock completion success (model=$targetModel) — ${content.length} chars")
            content
        }

    // ── Async HTTP ────────────────────────────────────────────────────────────

    private suspend fun executeAsync(request: Request): String =
        suspendCancellableCoroutine { cont ->
            val call = httpClient.newCall(request)
            cont.invokeOnCancellation { call.cancel() }
            call.enqueue(object : Callback {
                override fun onResponse(call: Call, response: Response) {
                    try {
                        val body = response.body?.string() ?: ""
                        if (!response.isSuccessful) {
                            Log.w(TAG, "Bedrock API error ${response.code}: $body")
                            cont.resumeWithException(
                                RuntimeException(
                                    runCatching { JSONObject(body).getString("message") }.getOrNull()
                                        ?: "AWS Bedrock HTTP ${response.code}"
                                )
                            )
                        } else {
                            cont.resume(body)
                        }
                    } catch (e: Exception) { cont.resumeWithException(e) }
                }
                override fun onFailure(call: Call, e: IOException) {
                    if (call.isCanceled()) return
                    cont.resumeWithException(e)
                }
            })
        }

    // ── SigV4 signing ─────────────────────────────────────────────────────────

    private fun buildSignedRequest(
        url: String,
        bodyString: String,
        region: String,
        accessKeyId: String,
        secretKey: String,
        sessionToken: String?,
    ): Request {
        val parsedUrl = URL(url)
        val host = parsedUrl.host
        val path = parsedUrl.path

        val dateFormat = SimpleDateFormat("yyyyMMdd", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }
        val dateTimeFormat = SimpleDateFormat("yyyyMMdd'T'HHmmss'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }
        val now = Date()
        val dateStamp     = dateFormat.format(now)
        val amzDate       = dateTimeFormat.format(now)
        val service       = "bedrock"
        val bodyBytes     = bodyString.toByteArray(Charsets.UTF_8)
        val payloadHash   = sha256Hex(bodyBytes)

        // Canonical headers
        val signedHeadersList = mutableListOf(
            "content-type" to "application/json",
            "host"         to host,
            "x-amz-content-sha256" to payloadHash,
            "x-amz-date"   to amzDate,
        )
        if (sessionToken != null) {
            signedHeadersList.add("x-amz-security-token" to sessionToken)
        }
        val sortedHeaders = signedHeadersList.sortedBy { it.first }
        val canonicalHeaders = sortedHeaders.joinToString("\n") { "${it.first}:${it.second}" } + "\n"
        val signedHeaders    = sortedHeaders.joinToString(";") { it.first }

        val canonicalRequest = listOf(
            "POST", path, "", canonicalHeaders, signedHeaders, payloadHash
        ).joinToString("\n")

        // String to sign
        val credentialScope = "$dateStamp/$region/$service/aws4_request"
        val stringToSign = "AWS4-HMAC-SHA256\n$amzDate\n$credentialScope\n${sha256Hex(canonicalRequest.toByteArray())}"

        // Signing key
        val signingKey = getSignatureKey(secretKey, dateStamp, region, service)
        val signature  = hmacHex(signingKey, stringToSign)

        val authorization = "AWS4-HMAC-SHA256 Credential=$accessKeyId/$credentialScope, " +
                "SignedHeaders=$signedHeaders, Signature=$signature"

        val requestBuilder = Request.Builder()
            .url(url)
            .header("Content-Type", "application/json")
            .header("Host", host)
            .header("x-amz-date", amzDate)
            .header("x-amz-content-sha256", payloadHash)
            .header("Authorization", authorization)
            .post(bodyString.toRequestBody(JSON_MEDIA_TYPE))

        if (sessionToken != null) {
            requestBuilder.header("x-amz-security-token", sessionToken)
        }

        return requestBuilder.build()
    }

    private fun sha256Hex(data: ByteArray): String {
        val digest = java.security.MessageDigest.getInstance("SHA-256")
        return digest.digest(data).joinToString("") { "%02x".format(it) }
    }

    private fun hmac(key: ByteArray, data: String): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key, "HmacSHA256"))
        return mac.doFinal(data.toByteArray(Charsets.UTF_8))
    }

    private fun hmacHex(key: ByteArray, data: String): String =
        hmac(key, data).joinToString("") { "%02x".format(it) }

    private fun getSignatureKey(key: String, dateStamp: String, region: String, service: String): ByteArray {
        val kDate    = hmac("AWS4$key".toByteArray(Charsets.UTF_8), dateStamp)
        val kRegion  = hmac(kDate, region)
        val kService = hmac(kRegion, service)
        return hmac(kService, "aws4_request")
    }

    companion object {
        private const val TAG = "BedrockAIProvider"
        private val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
    }
}
