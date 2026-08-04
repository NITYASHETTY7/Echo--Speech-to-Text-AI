package com.echo.dictation.speech.provider

import android.util.Base64
import android.util.Log
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
import java.io.File
import java.io.IOException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Google Gemini speech transcription provider.
 *
 * Model selection is handled entirely by [GeminiModelResolver]:
 *  - On every call, the resolver returns the best available model for the
 *    configured API key, using a fetch → rank → cache → fallback chain.
 *  - The `model` parameter received from the factory layer is ignored; all
 *    Gemini transcriptions go through the resolver.
 *  - If the API returns HTTP 404 or 410, the model is marked deprecated and
 *    transcription is retried automatically with the next-best candidate.
 *  - After [GeminiModelResolver.MAX_RETRIES] failed attempts the resolver throws
 *    [NoCompatibleGeminiModelException] and a user-friendly message is surfaced.
 *
 * POST /v1beta/models/{model}:generateContent
 * Header: x-goog-api-key: {apiKey}
 * Body: { "contents": [{ "parts": [ text-prompt, inline_data ] }] }
 * Response: candidates[0].content.parts[0].text
 */
class GeminiProvider(
    override val config: ProviderConfig,
    private val apiKey: String,
    private val httpClient: OkHttpClient,
    private val modelResolver: GeminiModelResolver,
) : SpeechProvider {

    private val baseUrl = config.defaultBaseUrl.trimEnd('/')

    override suspend fun transcribe(audioFile: File, model: String, language: String?): TranscriptionResult {
        require(audioFile.exists() && audioFile.length() > 0) { "Audio file is empty or missing" }

        Log.d(TAG, "=== GEMINI STT START === file=${audioFile.name} size=${audioFile.length()}B")

        val audioBytes  = audioFile.readBytes()
        val base64Audio = Base64.encodeToString(audioBytes, Base64.NO_WRAP)

        val prompt = buildString {
            append("Transcribe the following audio exactly in its original spoken language. ")
            if (!language.isNullOrBlank() && language.lowercase() != "auto") {
                append("The audio is in $language. ")
            }
            append("Do not translate. Return only the raw transcript text with no commentary.")
        }

        // ── Retry loop ────────────────────────────────────────────────────────
        var attempt = 0
        while (attempt < GeminiModelResolver.MAX_RETRIES) {
            attempt++

            val resolvedModel = try {
                modelResolver.resolveModel(apiKey)
            } catch (e: NoCompatibleGeminiModelException) {
                Log.e(TAG, "All Gemini models exhausted after $attempt attempt(s): ${e.message}")
                throw IOException(e.message ?: "No compatible Gemini models available.")
            }

            Log.d(TAG, "Attempt $attempt — model=$resolvedModel")

            val url = "$baseUrl/v1beta/models/$resolvedModel:generateContent"

            val requestJson = buildRequestJson(prompt, base64Audio)

            val request = Request.Builder()
                .url(url)
                .header("x-goog-api-key", apiKey)
                .header("Content-Type", "application/json")
                .post(requestJson.toRequestBody("application/json".toMediaType()))
                .build()

            val (httpCode, bodyText) = try {
                val response = executeAsync(request)
                Pair(response.first, response.second)
            } catch (e: UnknownHostException) {
                Log.e(TAG, "Network unavailable", e)
                throw e
            } catch (e: SocketTimeoutException) {
                Log.e(TAG, "Request timed out", e)
                throw e
            } catch (e: javax.net.ssl.SSLException) {
                Log.e(TAG, "SSL error", e)
                throw e
            } catch (e: IOException) {
                Log.e(TAG, "IOException: ${e.message}", e)
                throw e
            }

            Log.d(TAG, "HTTP $httpCode (attempt $attempt, model=$resolvedModel)")

            when {
                httpCode == 200 -> {
                    // ── Success path ──────────────────────────────────────────
                    val text = parseResponse(bodyText)
                    Log.d(TAG, "Transcript: \"${text.take(200)}\"")
                    Log.d(TAG, "=== GEMINI STT DONE === model=$resolvedModel")
                    return TranscriptionResult(text)
                }

                httpCode == 404 || httpCode == 410 || isModelUnavailableError(bodyText) -> {
                    // ── Deprecated model — mark and retry ─────────────────────
                    Log.w(TAG, "Model $resolvedModel returned $httpCode — marking deprecated, retrying…")
                    modelResolver.markDeprecated(resolvedModel, apiKey)
                    // Continue to next iteration
                }

                httpCode == 401 -> throw IOException("Gemini API key is invalid or missing (HTTP 401).")
                httpCode == 403 -> throw IOException("Gemini API key lacks permission (HTTP 403). Check key restrictions.")
                httpCode == 429 -> throw IOException("Gemini rate limit exceeded (HTTP 429). Try again later.")

                else -> {
                    Log.e(TAG, "Gemini HTTP $httpCode — body: $bodyText")
                    throw IOException("Gemini error HTTP $httpCode: $bodyText")
                }
            }
        }

        // Exhausted retries
        Log.e(TAG, "Exhausted $attempt retry attempts for Gemini STT")
        throw IOException("No compatible Gemini models are currently available for this API key.")
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun buildRequestJson(prompt: String, base64Audio: String): String =
        JSONObject().apply {
            put("contents", JSONArray().apply {
                put(JSONObject().apply {
                    put("parts", JSONArray().apply {
                        put(JSONObject().put("text", prompt))
                        put(JSONObject().apply {
                            put("inline_data", JSONObject().apply {
                                put("mime_type", "audio/mp4")
                                put("data", base64Audio)
                            })
                        })
                    })
                })
            })
        }.toString()

    private fun parseResponse(json: String): String = try {
        JSONObject(json)
            .getJSONArray("candidates")
            .getJSONObject(0)
            .getJSONObject("content")
            .getJSONArray("parts")
            .getJSONObject(0)
            .optString("text", "")
            .trim()
    } catch (e: Exception) {
        Log.e(TAG, "Failed to parse Gemini STT response: ${e.message}")
        ""
    }

    /**
     * Returns true when the response body contains a known "model no longer
     * available" error pattern that Gemini embeds in 200-ish responses or
     * structured error bodies.
     */
    private fun isModelUnavailableError(body: String): Boolean {
        val lower = body.lowercase()
        return lower.contains("model is no longer available") ||
               lower.contains("model not found") ||
               lower.contains("not found for api version")
    }

    /**
     * Executes an OkHttp [Request] asynchronously, returns Pair(httpCode, body).
     * Cancels the OkHttp call when the coroutine is cancelled.
     */
    private suspend fun executeAsync(request: Request): Pair<Int, String> =
        suspendCancellableCoroutine { cont ->
            val call = httpClient.newCall(request)
            cont.invokeOnCancellation {
                Log.d(TAG, "Coroutine cancelled — cancelling OkHttp call")
                call.cancel()
            }
            call.enqueue(object : Callback {
                override fun onResponse(call: Call, response: Response) {
                    try {
                        val body = response.body?.string() ?: ""
                        cont.resume(Pair(response.code, body))
                    } catch (e: Exception) {
                        cont.resumeWithException(e)
                    }
                }
                override fun onFailure(call: Call, e: IOException) {
                    if (call.isCanceled()) return
                    Log.e(TAG, "OkHttp failure: ${e.message}", e)
                    cont.resumeWithException(e)
                }
            })
        }

    companion object {
        private const val TAG = "GeminiProvider"
    }
}
