package com.echo.dictation.speech.provider

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.Response
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

/**
 * Handles providers that implement the OpenAI audio transcription API:
 * Groq, OpenAI, OpenRouter, Azure OpenAI, and any Custom endpoint.
 *
 * Uses OkHttp's async [Call.enqueue] wrapped in [suspendCancellableCoroutine]
 * so the coroutine is properly cancellable and the OkHttp call is cancelled
 * when the coroutine is cancelled (e.g. user taps the orange pill).
 */
class OpenAICompatibleProvider(
    override val config: ProviderConfig,
    private val apiKey: String,
    private val baseUrl: String,
    private val httpClient: OkHttpClient,
) : SpeechProvider {

    override suspend fun transcribe(audioFile: File, model: String, language: String?): TranscriptionResult {
        Log.d(TAG, "=== TRANSCRIBE START ===")
        Log.d(TAG, "[1] provider  : ${config.displayName}")
        Log.d(TAG, "[2] apiKey    : present=true  length=${apiKey.length}")
        Log.d(TAG, "[3] model     : $model")
        Log.d(TAG, "[4] baseUrl   : $baseUrl")
        Log.d(TAG, "[5] file      : ${audioFile.name}  exists=${audioFile.exists()}  size=${audioFile.length()}B")
        Log.d(TAG, "[6] language  : ${language ?: "(auto)"}")
        Log.d(TAG, "[7] thread    : ${Thread.currentThread().name}")

        require(audioFile.exists() && audioFile.length() > 0) { "Audio file is empty or missing" }

        val url = baseUrl.trimEnd('/') + "/audio/transcriptions"
        Log.d(TAG, "[8] full URL  : $url")

        // ── Build multipart body ──────────────────────────────────────────────
        Log.d(TAG, "[9] building multipart body…")
        val fileBody = audioFile.asRequestBody("audio/mp4".toMediaType())
        val multipartBody = okhttp3.MultipartBody.Builder()
            .setType(okhttp3.MultipartBody.FORM)
            .addFormDataPart("file", audioFile.name, fileBody)
            .addFormDataPart("model", model)
            .addFormDataPart("response_format", "verbose_json")
            .addFormDataPart("temperature", "0")
            .addFormDataPart("prompt", PROMPT)
            .also { builder ->
                if (!language.isNullOrBlank() && language.lowercase() != "auto") {
                    builder.addFormDataPart("language", language)
                }
            }
            .build()

        val authValue = config.authValueFormat.format(apiKey)
        val request = Request.Builder()
            .url(url)
            .header(config.authHeaderName, authValue)
            .post(multipartBody)
            .build()

        Log.d(TAG, "[10] multipart parts: file=${audioFile.name}, model=$model, response_format=verbose_json")
        Log.d(TAG, "[11] auth header    : ${config.authHeaderName}: ${config.authValueFormat.format("[KEY]")}")

        // ── Execute HTTP request (async, cancellable) ─────────────────────────
        Log.d(TAG, "[12] enqueuing HTTP request…")

        val responseBody = suspendCancellableCoroutine<String> { continuation ->
            val call = httpClient.newCall(request)

            // Cancel the OkHttp call when the coroutine is cancelled
            continuation.invokeOnCancellation {
                Log.d(TAG, "[12] coroutine cancelled — cancelling OkHttp call")
                call.cancel()
            }

            call.enqueue(object : Callback {
                override fun onResponse(call: Call, response: Response) {
                    Log.d(TAG, "[13] HTTP response received")
                    Log.d(TAG, "[14] HTTP status code : ${response.code}")
                    try {
                        val body = response.body?.string() ?: ""
                        Log.d(TAG, "[15] response body length : ${body.length} chars")
                        if (!response.isSuccessful) {
                            Log.e(TAG, "[15] HTTP ${response.code} ERROR body: $body")
                            continuation.resumeWithException(
                                IOException("HTTP ${response.code}: $body")
                            )
                        } else {
                            Log.d(TAG, "[16] success — resuming coroutine with body")
                            continuation.resume(body)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "[15] exception reading response body: ${e.message}", e)
                        continuation.resumeWithException(e)
                    }
                }

                override fun onFailure(call: Call, e: IOException) {
                    if (call.isCanceled()) {
                        Log.d(TAG, "[13] OkHttp call cancelled (coroutine was cancelled)")
                        // Don't resume — the continuation is already cancelled
                        return
                    }
                    Log.e(TAG, "[13] OkHttp onFailure: ${e::class.java.name}: ${e.message}", e)
                    continuation.resumeWithException(e)
                }
            })
        }

        // ── Parse response ─────────────────────────────────────────────────────
        Log.d(TAG, "[17] parsing transcript from response…")
        val text = parseTranscriptText(responseBody)
        Log.d(TAG, "[18] parsed text length : ${text.length}")
        Log.d(TAG, "[19] transcript : \"${text.take(200)}\"")

        if (text.isEmpty()) {
            Log.d(TAG, "[20] empty text — returning empty TranscriptionResult")
            return TranscriptionResult("")
        }

        val filtered = applyHallucinationGuard(responseBody, text)
        Log.d(TAG, "[20] after hallucination guard : \"${filtered.take(200)}\"")
        Log.d(TAG, "=== TRANSCRIBE DONE ===")
        return TranscriptionResult(filtered)
    }

    private fun parseTranscriptText(json: String): String = try {
        JSONObject(json).optString("text", "").trim()
    } catch (e: Exception) {
        Log.e(TAG, "parseTranscriptText failed: ${e.message}")
        ""
    }

    private fun applyHallucinationGuard(json: String, text: String): String {
        try {
            val root = JSONObject(json)
            val segments = root.optJSONArray("segments")
            if (segments != null && segments.length() > 0) {
                var sum = 0.0
                var max = 0.0
                for (i in 0 until segments.length()) {
                    val prob = segments.getJSONObject(i).optDouble("no_speech_prob", 0.0)
                    sum += prob
                    if (prob > max) max = prob
                }
                val avg = sum / segments.length()
                Log.d(TAG, "no_speech_prob: avg=${"%.3f".format(avg)} max=${"%.3f".format(max)} segments=${segments.length()}")
                if (avg >= NO_SPEECH_AVG_THRESHOLD || max >= NO_SPEECH_MAX_THRESHOLD) {
                    Log.w(TAG, "Hallucination discarded: \"$text\"")
                    return ""
                }
            }
        } catch (_: Exception) {}

        if (text.lowercase() in HALLUCINATION_PHRASES) {
            Log.w(TAG, "Known hallucination phrase discarded: \"$text\"")
            return ""
        }
        return text
    }

    companion object {
        private const val TAG = "OpenAICompatProvider"
        private const val NO_SPEECH_AVG_THRESHOLD = 0.6
        private const val NO_SPEECH_MAX_THRESHOLD = 0.8
        private const val PROMPT = "Echo."
        private val HALLUCINATION_PHRASES = setOf(
            "you", "thank you.", "thank you", "thanks.", "thanks",
            ".", "..", "...", "bye.", "bye",
            "subtitles by", "subtitles by the amara.org community",
        )
    }
}
