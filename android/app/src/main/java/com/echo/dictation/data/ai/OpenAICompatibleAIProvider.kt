package com.echo.dictation.data.ai

import android.util.Log
import com.echo.dictation.domain.ai.AIProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject

/**
 * Generic OpenAI-compatible Chat Completions provider.
 *
 * Covers: OpenAI, OpenRouter, Azure OpenAI, and any Custom OpenAI-compatible endpoint.
 * Azure uses `api-key` header instead of `Authorization: Bearer`.
 */
class OpenAICompatibleAIProvider(
    override val id: String,
    override val name: String,
    override val defaultModel: String,
    private val baseUrl: String,
    private val apiKey: String,
    private val httpClient: OkHttpClient,
    private val authHeaderName: String = "Authorization",
    private val authValueFormat: String = "Bearer %s",
    private val extraHeaders: Map<String, String> = emptyMap(),
) : AIProvider {

    override suspend fun generateCompletion(
        systemPrompt: String?,
        userPrompt: String,
        modelOverride: String?
    ): Result<String> = withContext(Dispatchers.IO) {
        runCatching {
            val targetModel = modelOverride?.takeIf { it.isNotBlank() } ?: defaultModel

            val messages = JSONArray().apply {
                if (!systemPrompt.isNullOrBlank()) {
                    put(JSONObject().put("role", "system").put("content", systemPrompt))
                }
                put(JSONObject().put("role", "user").put("content", userPrompt))
            }

            val body = JSONObject()
                .put("model", targetModel)
                .put("messages", messages)
                .put("temperature", 0.2)
                .put("max_tokens", 4096)
                .toString()
                .toRequestBody(JSON_MEDIA_TYPE)

            val url = "${baseUrl.trimEnd('/')}/chat/completions"
            val authValue = authValueFormat.format(apiKey)

            val requestBuilder = Request.Builder()
                .url(url)
                .header(authHeaderName, authValue)
                .header("Content-Type", "application/json")
                .post(body)

            extraHeaders.forEach { (k, v) -> requestBuilder.header(k, v) }

            val response = httpClient.newCall(requestBuilder.build()).execute()
            val responseBody = response.body?.string() ?: ""

            if (!response.isSuccessful) {
                Log.w(TAG, "$name API error ${response.code}: $responseBody")
                throw parseHttpError(response.code, responseBody, name)
            }

            val content = JSONObject(responseBody)
                .getJSONArray("choices")
                .getJSONObject(0)
                .getJSONObject("message")
                .getString("content")
                .trim()

            Log.d(TAG, "$name completion success (model=$targetModel) — ${content.length} chars")
            content
        }
    }

    companion object {
        private const val TAG = "OpenAICompatibleAIProvider"
        private val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
    }
}

internal fun parseHttpError(code: Int, body: String, providerName: String): Exception {
    val message = runCatching {
        JSONObject(body).getJSONObject("error").getString("message")
    }.getOrNull()
    return when (code) {
        401  -> IllegalStateException(message ?: "Invalid $providerName API key (HTTP 401)")
        429  -> RuntimeException(message ?: "$providerName rate limit or quota exceeded (HTTP 429)")
        else -> RuntimeException(message ?: "$providerName API request failed with HTTP $code")
    }
}
