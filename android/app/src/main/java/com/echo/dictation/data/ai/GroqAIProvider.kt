package com.echo.dictation.data.ai

import android.util.Log
import com.echo.dictation.domain.ai.AIProvider
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

@Singleton
class GroqAIProvider @Inject constructor(
    private val keyStore: ProviderKeyStore,
    private val httpClient: OkHttpClient,
) : AIProvider {

    override val id: String = "groq"
    override val name: String = "Groq"
    override val defaultModel: String = MODEL_LLAMA_3_3_70B

    override suspend fun generateCompletion(
        systemPrompt: String?,
        userPrompt: String,
        modelOverride: String?
    ): Result<String> = withContext(Dispatchers.IO) {
        runCatching {
            val apiKey = keyStore.getKey(ProviderId.GROQ)
                ?: throw IllegalStateException("Groq API key is not configured. Please add your key in Settings.")

            val targetModel = modelOverride?.ifBlank { defaultModel } ?: defaultModel

            val messages = JSONArray().apply {
                if (!systemPrompt.isNullOrBlank()) {
                    put(JSONObject().put("role", "system").put("content", systemPrompt))
                }
                put(JSONObject().put("role", "user").put("content", userPrompt))
            }

            val bodyJson = JSONObject()
                .put("model", targetModel)
                .put("messages", messages)
                .put("temperature", 0.2)
                .put("max_tokens", 4096)
                .toString()

            val requestBody = bodyJson.toRequestBody(JSON_MEDIA_TYPE)

            val request = Request.Builder()
                .url("${BASE_URL}chat/completions")
                .header("Authorization", "Bearer $apiKey")
                .header("Content-Type", "application/json")
                .post(requestBody)
                .build()

            val response = httpClient.newCall(request).execute()
            val responseBody = response.body?.string() ?: ""

            if (!response.isSuccessful) {
                Log.w(TAG, "Groq API error ${response.code}: $responseBody")
                throw parseHttpError(response.code, responseBody)
            }

            val jsonRoot = JSONObject(responseBody)
            val choices = jsonRoot.getJSONArray("choices")
            if (choices.length() == 0) {
                throw IllegalStateException("Empty choices array in Groq response")
            }

            val content = choices.getJSONObject(0)
                .getJSONObject("message")
                .getString("content")
                .trim()

            Log.d(TAG, "Groq completion success — output ${content.length} chars")
            content
        }
    }

    private fun parseHttpError(code: Int, body: String): Exception {
        val message = runCatching {
            JSONObject(body).getJSONObject("error").getString("message")
        }.getOrNull()

        return when (code) {
            401 -> IllegalStateException(message ?: "Invalid Groq API key (HTTP 401)")
            429 -> RuntimeException(message ?: "Groq rate limit or quota exceeded (HTTP 429)")
            else -> RuntimeException(message ?: "Groq API request failed with HTTP $code")
        }
    }

    companion object {
        private const val TAG = "GroqAIProvider"
        private const val BASE_URL = "https://api.groq.com/openai/v1/"
        const val MODEL_LLAMA_3_3_70B = "llama-3.3-70b-versatile"
        private val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
    }
}
