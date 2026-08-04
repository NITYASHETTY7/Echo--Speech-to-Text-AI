package com.echo.dictation.data.ai

import android.util.Log
import com.echo.dictation.domain.ai.AIProvider
import com.echo.dictation.speech.provider.GeminiModelResolver
import com.echo.dictation.speech.provider.NoCompatibleGeminiModelException
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
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Google Gemini AI text generation provider.
 *
 * Model selection is handled entirely by [GeminiModelResolver]:
 *  - The resolver returns the best available model for the configured API key
 *    using a fetch → rank → cache → fallback chain (identical to the STT path).
 *  - No hardcoded model name is used.  The resolver's built-in fallback list is
 *    the last resort when the network is unavailable.
 *  - If the API returns HTTP 404 or 410 for a given model, that model is marked
 *    deprecated and the call is retried automatically with the next candidate.
 *  - After [GeminiModelResolver.MAX_RETRIES] failed attempts a user-friendly
 *    error is thrown.
 *
 * Endpoint: POST /v1beta/models/{model}:generateContent?key={apiKey}
 */
class GeminiAIProvider(
    private val apiKey: String,
    private val httpClient: OkHttpClient,
    private val modelResolver: GeminiModelResolver,
) : AIProvider {

    override val id: String = "gemini"
    override val name: String = "Google Gemini"

    /**
     * The defaultModel is resolved dynamically; returning the first built-in
     * fallback satisfies the [AIProvider.defaultModel] contract while ensuring
     * no hardcoded production model name leaks into higher layers.
     */
    override val defaultModel: String
        get() = GeminiModelResolver.BUILT_IN_FALLBACKS.first()

    override suspend fun generateCompletion(
        systemPrompt: String?,
        userPrompt: String,
        modelOverride: String?,
    ): Result<String> = runCatching {
        executeWithFallback(systemPrompt, userPrompt, modelOverride)
    }

    // ── Core execution with retry loop ────────────────────────────────────────

    private suspend fun executeWithFallback(
        systemPrompt: String?,
        userPrompt: String,
        modelOverride: String?,
    ): String {
        // If the caller supplies an explicit model override, try it first.
        // If it's deprecated, the resolver will skip it automatically once
        // markDeprecated() has been called (the override is essentially treated
        // as a "hint", not a mandate).
        var attempt = 0
        var forcedModel: String? = modelOverride?.takeIf { it.isNotBlank() }

        while (attempt < GeminiModelResolver.MAX_RETRIES) {
            attempt++

            val resolvedModel = try {
                if (forcedModel != null) {
                    // Use the forced model on the first attempt; after that let the
                    // resolver decide (it will skip deprecated entries).
                    val m = forcedModel!!
                    forcedModel = null          // clear so subsequent retries use resolver
                    Log.d(TAG, "Attempt $attempt — using model override: $m")
                    m
                } else {
                    modelResolver.resolveModel(apiKey).also { m ->
                        Log.d(TAG, "Attempt $attempt — resolver selected: $m")
                    }
                }
            } catch (e: NoCompatibleGeminiModelException) {
                Log.e(TAG, "All Gemini AI models exhausted: ${e.message}")
                throw RuntimeException(
                    e.message ?: "No compatible Gemini models are available for this API key."
                )
            }

            val bodyJson = buildRequestBody(systemPrompt, userPrompt)
            val url = "${BASE_URL}${resolvedModel}:generateContent?key=$apiKey"

            val request = Request.Builder()
                .url(url)
                .header("Content-Type", "application/json")
                .post(bodyJson.toRequestBody(JSON_MEDIA_TYPE))
                .build()

            val (code, body) = try {
                executeAsync(request)
            } catch (e: Exception) {
                Log.e(TAG, "Network error on attempt $attempt: ${e.message}")
                throw e
            }

            Log.d(TAG, "HTTP $code (attempt $attempt, model=$resolvedModel)")

            when {
                code == 200 -> {
                    val content = parseResponse(body)
                    if (content.isBlank()) throw IllegalStateException("Empty response from Gemini model $resolvedModel")
                    Log.d(TAG, "Gemini AI success — model=$resolvedModel  chars=${content.length}")
                    return content
                }

                code == 404 || code == 410 || isModelUnavailableError(body) -> {
                    Log.w(TAG, "Model $resolvedModel returned $code — marking deprecated, retrying…")
                    modelResolver.markDeprecated(resolvedModel, apiKey)
                    // loop continues
                }

                code == 401 ->
                    throw RuntimeException("Gemini API key is invalid or missing (HTTP 401).")
                code == 403 ->
                    throw RuntimeException("Gemini API key lacks permission (HTTP 403). Check key restrictions.")
                code == 429 ->
                    throw RuntimeException("Gemini rate limit exceeded (HTTP 429). Try again later.")

                else -> {
                    Log.e(TAG, "Gemini AI error HTTP $code: $body")
                    throw parseHttpError(code, body, "Google Gemini")
                }
            }
        }

        Log.e(TAG, "Exhausted $attempt retry attempts for Gemini AI text generation")
        throw RuntimeException("No compatible Gemini models are currently available for this API key.")
    }

    // ── Request / response helpers ────────────────────────────────────────────

    private fun buildRequestBody(systemPrompt: String?, userPrompt: String): String {
        val obj = JSONObject()

        if (!systemPrompt.isNullOrBlank()) {
            obj.put(
                "system_instruction",
                JSONObject().put("parts", JSONArray().put(JSONObject().put("text", systemPrompt)))
            )
        }

        obj.put(
            "contents",
            JSONArray().put(
                JSONObject()
                    .put("role", "user")
                    .put("parts", JSONArray().put(JSONObject().put("text", userPrompt)))
            )
        )

        obj.put(
            "generationConfig",
            JSONObject()
                .put("temperature", 0.2)
                .put("maxOutputTokens", 4096)
        )

        return obj.toString()
    }

    private fun parseResponse(json: String): String = try {
        JSONObject(json)
            .getJSONArray("candidates")
            .getJSONObject(0)
            .getJSONObject("content")
            .getJSONArray("parts")
            .getJSONObject(0)
            .getString("text")
            .trim()
    } catch (e: Exception) {
        Log.e(TAG, "Failed to parse Gemini AI response: ${e.message}")
        ""
    }

    private fun isModelUnavailableError(body: String): Boolean {
        val lower = body.lowercase()
        return lower.contains("model is no longer available") ||
               lower.contains("model not found") ||
               lower.contains("not found for api version")
    }

    // ── Async HTTP ────────────────────────────────────────────────────────────

    private suspend fun executeAsync(request: Request): Pair<Int, String> =
        suspendCancellableCoroutine { cont ->
            val call = httpClient.newCall(request)
            cont.invokeOnCancellation { call.cancel() }
            call.enqueue(object : Callback {
                override fun onResponse(call: Call, response: Response) {
                    try {
                        val body = response.body?.string() ?: ""
                        cont.resume(Pair(response.code, body))
                    } catch (e: Exception) { cont.resumeWithException(e) }
                }
                override fun onFailure(call: Call, e: IOException) {
                    if (call.isCanceled()) return
                    cont.resumeWithException(e)
                }
            })
        }

    companion object {
        private const val TAG      = "GeminiAIProvider"
        private const val BASE_URL = "https://generativelanguage.googleapis.com/v1beta/models/"
        private val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
    }
}
