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
 * Google Gemini AI provider using the Gemini REST API (generateContent endpoint).
 *
 * Default model: gemini-2.5-flash
 * System instructions are sent as a top-level `system_instruction` field (Gemini's format).
 */
class GeminiAIProvider(
    private val apiKey: String,
    private val httpClient: OkHttpClient,
    private val modelOverride: String? = null,
) : AIProvider {

    override val id: String = "gemini"
    override val name: String = "Google Gemini"
    override val defaultModel: String = modelOverride?.ifBlank { null } ?: DEFAULT_MODEL

    override suspend fun generateCompletion(
        systemPrompt: String?,
        userPrompt: String,
        modelOverride: String?
    ): Result<String> = withContext(Dispatchers.IO) {
        runCatching {
            val model = modelOverride?.takeIf { it.isNotBlank() } ?: defaultModel

            // Build request body in Gemini format
            val bodyObj = JSONObject()

            // System instruction (optional)
            if (!systemPrompt.isNullOrBlank()) {
                bodyObj.put(
                    "system_instruction",
                    JSONObject().put(
                        "parts",
                        JSONArray().put(JSONObject().put("text", systemPrompt))
                    )
                )
            }

            // User message
            bodyObj.put(
                "contents",
                JSONArray().put(
                    JSONObject()
                        .put("role", "user")
                        .put(
                            "parts",
                            JSONArray().put(JSONObject().put("text", userPrompt))
                        )
                )
            )

            // Generation config
            bodyObj.put(
                "generationConfig",
                JSONObject()
                    .put("temperature", 0.2)
                    .put("maxOutputTokens", 4096)
            )

            val url = "${BASE_URL}${model}:generateContent?key=$apiKey"
            val requestBody = bodyObj.toString().toRequestBody(JSON_MEDIA_TYPE)

            val request = Request.Builder()
                .url(url)
                .header("Content-Type", "application/json")
                .post(requestBody)
                .build()

            val response = httpClient.newCall(request).execute()
            val responseBody = response.body?.string() ?: ""

            if (!response.isSuccessful) {
                Log.w(TAG, "Gemini API error ${response.code}: $responseBody")
                val errorMsg = runCatching {
                    JSONObject(responseBody)
                        .getJSONArray("error")
                        .getJSONObject(0)
                        .getString("message")
                }.getOrNull() ?: runCatching {
                    JSONObject(responseBody).getJSONObject("error").getString("message")
                }.getOrNull()
                throw parseHttpError(response.code, responseBody, "Google Gemini")
            }

            // Parse Gemini response format
            val content = JSONObject(responseBody)
                .getJSONArray("candidates")
                .getJSONObject(0)
                .getJSONObject("content")
                .getJSONArray("parts")
                .getJSONObject(0)
                .getString("text")
                .trim()

            Log.d(TAG, "Gemini completion success (model=$model) — ${content.length} chars")
            content
        }
    }

    companion object {
        private const val TAG = "GeminiAIProvider"
        private const val BASE_URL = "https://generativelanguage.googleapis.com/v1beta/models/"
        private const val DEFAULT_MODEL = "gemini-2.5-flash"
        private val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
    }
}
