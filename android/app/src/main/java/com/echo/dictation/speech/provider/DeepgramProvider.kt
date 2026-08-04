package com.echo.dictation.speech.provider

import android.util.Log
import kotlinx.coroutines.suspendCancellableCoroutine
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
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Deepgram pre-recorded audio transcription.
 *
 * POST raw audio bytes to /v1/listen with query params:
 *   ?model={model}&smart_format=true
 *
 * Auth header: Authorization: Token {apiKey}
 * Content-Type: audio/mp4
 *
 * Response JSON path: results.channels[0].alternatives[0].transcript
 *
 * Uses OkHttp async [Call.enqueue] wrapped in [suspendCancellableCoroutine] so the
 * coroutine is cancellable mid-flight and holds no dispatcher threads while waiting.
 */
class DeepgramProvider(
    override val config: ProviderConfig,
    private val apiKey: String,
    private val httpClient: OkHttpClient,
) : SpeechProvider {

    override suspend fun transcribe(audioFile: File, model: String, language: String?): TranscriptionResult {
        require(audioFile.exists() && audioFile.length() > 0) { "Audio file is empty or missing" }

        val urlBuilder = StringBuilder("${config.defaultBaseUrl.trimEnd('/')}/v1/listen")
            .append("?model=").append(model)
            .append("&smart_format=true")
        if (!language.isNullOrBlank() && language.lowercase() != "auto") {
            urlBuilder.append("&language=").append(language)
        }
        val url = urlBuilder.toString()

        Log.d(TAG, "=== DEEPGRAM TRANSCRIBE START ===")
        Log.d(TAG, "url  : $url")
        Log.d(TAG, "file : ${audioFile.name}  size=${audioFile.length()}B")

        val request = Request.Builder()
            .url(url)
            .header("Authorization", config.authValueFormat.format(apiKey))
            .post(audioFile.asRequestBody("audio/mp4".toMediaType()))
            .build()

        val responseText = suspendCancellableCoroutine<String> { cont ->
            val call = httpClient.newCall(request)
            cont.invokeOnCancellation {
                Log.d(TAG, "Coroutine cancelled — cancelling OkHttp call")
                call.cancel()
            }
            call.enqueue(object : Callback {
                override fun onResponse(call: Call, response: Response) {
                    try {
                        val body = response.body?.string() ?: ""
                        Log.d(TAG, "HTTP ${response.code}")
                        if (!response.isSuccessful) {
                            Log.e(TAG, "HTTP ${response.code} — body: $body")
                            cont.resumeWithException(IOException("Deepgram HTTP ${response.code}: $body"))
                        } else {
                            cont.resume(body)
                        }
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

        val transcript = parseTranscript(responseText)
        Log.d(TAG, "transcript: \"${transcript.take(200)}\"")
        Log.d(TAG, "=== DEEPGRAM TRANSCRIBE DONE ===")
        return TranscriptionResult(transcript)
    }

    private fun parseTranscript(json: String): String = try {
        val root = JSONObject(json)
        root.getJSONObject("results")
            .getJSONArray("channels")
            .getJSONObject(0)
            .getJSONArray("alternatives")
            .getJSONObject(0)
            .optString("transcript", "")
            .trim()
    } catch (e: Exception) {
        Log.e(TAG, "Failed to parse Deepgram response: ${e.message}")
        ""
    }

    companion object {
        private const val TAG = "DeepgramProvider"
    }
}
