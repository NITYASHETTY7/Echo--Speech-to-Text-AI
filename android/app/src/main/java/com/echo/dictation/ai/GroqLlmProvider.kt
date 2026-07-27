package com.echo.dictation.ai

import android.util.Log
import com.echo.dictation.speech.provider.ProviderId
import com.echo.dictation.speech.provider.ProviderKeyStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import javax.inject.Inject
import javax.inject.Singleton

/**
 * LLM provider backed by the Groq Chat Completions API.
 *
 * Uses the existing [ProviderKeyStore] so the user's Groq API key (already
 * stored for speech transcription) is reused — no new credential management.
 *
 * Model: llama-3.3-70b-versatile — the latest production-ready Llama model on Groq.
 *
 * The implementation is intentionally self-contained: it does NOT share code with
 * [com.echo.dictation.speech.provider.OpenAICompatibleProvider] because the speech
 * layer accepts audio files (multipart), while this layer sends JSON chat messages.
 */
@Singleton
class GroqLlmProvider @Inject constructor(
    private val keyStore: ProviderKeyStore,
    private val httpClient: OkHttpClient,
) : LlmProvider {

    override val name: String = "Groq ($MODEL)"

    override suspend fun complete(systemPrompt: String?, userPrompt: String): LlmResult =
        withContext(Dispatchers.IO) {
            try {
                val apiKey = keyStore.getKey(ProviderId.GROQ)
                    ?: return@withContext LlmResult.Failure(
                        IllegalStateException("No Groq API key configured. Go to Settings → Provider → Groq to add your key."),
                        "Groq API key not configured",
                    )

                val messages = JSONArray().apply {
                    if (systemPrompt != null) {
                        put(JSONObject().put("role", "system").put("content", systemPrompt))
                    }
                    put(JSONObject().put("role", "user").put("content", userPrompt))
                }

                val body = JSONObject()
                    .put("model", MODEL)
                    .put("messages", messages)
                    .put("temperature", 0.3)
                    .put("max_tokens", 4096)
                    .toString()
                    .toRequestBody(JSON_MEDIA_TYPE)

                val request = Request.Builder()
                    .url("${BASE_URL}chat/completions")
                    .header("Authorization", "Bearer $apiKey")
                    .header("Content-Type", "application/json")
                    .post(body)
                    .build()

                val response = httpClient.newCall(request).execute()
                val responseBody = response.body?.string() ?: ""

                if (!response.isSuccessful) {
                    Log.w(TAG, "Groq LLM error ${response.code}: $responseBody")
                    return@withContext LlmResult.Failure(
                        RuntimeException("HTTP ${response.code}"),
                        parseErrorMessage(responseBody, response.code),
                    )
                }

                val content = JSONObject(responseBody)
                    .getJSONArray("choices")
                    .getJSONObject(0)
                    .getJSONObject("message")
                    .getString("content")
                    .trim()

                Log.d(TAG, "Groq LLM success — output length=${content.length}")
                LlmResult.Success(content)

            } catch (e: UnknownHostException) {
                Log.e(TAG, "Network unavailable", e)
                LlmResult.Failure(e, "Network unavailable — cannot reach Groq API")
            } catch (e: SocketTimeoutException) {
                Log.e(TAG, "Request timed out", e)
                LlmResult.Failure(e, "Request timed out — please try again")
            } catch (e: Exception) {
                Log.e(TAG, "Unexpected error", e)
                LlmResult.Failure(e, e.message ?: "An unexpected error occurred")
            }
        }

    private fun parseErrorMessage(body: String, code: Int): String = runCatching {
        JSONObject(body).getJSONObject("error").getString("message")
    }.getOrElse {
        when (code) {
            401  -> "Invalid Groq API key (HTTP 401)"
            403  -> "Access forbidden (HTTP 403) — check your Groq account"
            429  -> "Rate limit exceeded — please wait before retrying"
            503  -> "Groq service temporarily unavailable (HTTP 503)"
            else -> "Groq API error (HTTP $code)"
        }
    }

    companion object {
        private const val TAG      = "GroqLlmProvider"
        private const val BASE_URL = "https://api.groq.com/openai/v1/"
        /** Latest production-ready Llama model on Groq at the time of writing. */
        const val MODEL = "llama-3.3-70b-versatile"
        private val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
    }
}
