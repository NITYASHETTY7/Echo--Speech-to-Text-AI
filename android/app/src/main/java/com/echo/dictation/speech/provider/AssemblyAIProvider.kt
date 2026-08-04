package com.echo.dictation.speech.provider

import android.util.Log
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * AssemblyAI transcription via the synchronous REST API.
 *
 * Step 1 – Upload audio:
 *   POST /v2/upload  (raw bytes, Content-Type: audio/mp4)
 *   → response: { "upload_url": "..." }
 *
 * Step 2 – Request transcription:
 *   POST /v2/transcript  { "audio_url": "...", "language_code": "..." }
 *   → response: { "id": "...", "status": "queued" }
 *
 * Step 3 – Poll until status = "completed" or "error".
 *
 * Polling schedule: start at 1 s, then every 1.5 s.
 * For short recordings (1-2 sentences) AssemblyAI typically completes in 3-8 s,
 * so the fast initial poll catches the result on the 2nd or 3rd attempt instead
 * of the 3rd–5th attempt with the old 2 s interval.
 *
 * All HTTP calls are wrapped in [suspendCancellableCoroutine] so the coroutine
 * (and the underlying OkHttp call) is cancelled when the user taps the orange pill.
 *
 * Auth: "Authorization: {key}"  (no "Bearer" prefix)
 */
class AssemblyAIProvider(
    override val config: ProviderConfig,
    private val apiKey: String,
    private val httpClient: OkHttpClient,
) : SpeechProvider {

    private val baseUrl = config.defaultBaseUrl.trimEnd('/')

    override suspend fun transcribe(audioFile: File, model: String, language: String?): TranscriptionResult {
        require(audioFile.exists() && audioFile.length() > 0) { "Audio file is empty or missing" }

        Log.d(TAG, "=== ASSEMBLYAI TRANSCRIBE START ===")
        Log.d(TAG, "file: ${audioFile.name}  size=${audioFile.length()}B")

        // ── Step 1: upload audio ─────────────────────────────────────────────
        Log.d(TAG, "Step 1: uploading audio…")
        val uploadUrl = uploadAudio(audioFile)
        Log.d(TAG, "Upload URL received")

        // ── Step 2: submit transcription request ──────────────────────────────
        Log.d(TAG, "Step 2: submitting transcription request…")
        val jobBody = JSONObject().apply {
            put("audio_url", uploadUrl)
            if (!language.isNullOrBlank() && language.lowercase() != "auto") {
                put("language_code", language)
            }
        }.toString()

        val submitRequest = Request.Builder()
            .url("$baseUrl/v2/transcript")
            .header("Authorization", apiKey)
            .header("Content-Type", "application/json")
            .post(jobBody.toRequestBody("application/json".toMediaType()))
            .build()

        val transcriptId = executeAsync(submitRequest).let { json ->
            JSONObject(json).optString("id")
                .also { Log.d(TAG, "Transcript ID: $it") }
        }
        check(transcriptId.isNotBlank()) { "AssemblyAI did not return a transcript ID" }

        // ── Step 3: poll for completion ───────────────────────────────────────
        // Polling schedule:
        //   Poll 1: after INITIAL_POLL_MS  (1 s)  — catch very fast completions
        //   Polls 2–N: every POLL_INTERVAL_MS (1.5 s) — tight loop for short audio
        //
        // For a 1–2 sentence recording AssemblyAI usually completes in 3–8 s,
        // so we expect completion on poll 2–5 (at t=2.5–7 s) instead of the old
        // t=4–10 s with a 2 s interval.
        Log.d(TAG, "Step 3: polling for completion (initial=${INITIAL_POLL_MS}ms, interval=${POLL_INTERVAL_MS}ms)…")
        var attempts = 0

        delay(INITIAL_POLL_MS)   // wait once before the first poll

        while (attempts < MAX_POLL_ATTEMPTS) {
            attempts++
            val pollRequest = Request.Builder()
                .url("$baseUrl/v2/transcript/$transcriptId")
                .header("Authorization", apiKey)
                .get()
                .build()

            val pollJson = executeAsync(pollRequest)
            val status = JSONObject(pollJson).optString("status")
            Log.d(TAG, "Poll #$attempts  status=$status")

            when (status) {
                "completed" -> {
                    val text = JSONObject(pollJson).optString("text", "").trim()
                    Log.d(TAG, "transcript: \"${text.take(200)}\"")
                    Log.d(TAG, "=== ASSEMBLYAI TRANSCRIBE DONE ===")
                    return TranscriptionResult(text)
                }
                "error" -> {
                    val err = JSONObject(pollJson).optString("error", "Unknown error")
                    throw IOException("AssemblyAI transcription error: $err")
                }
                // "queued" or "processing" — wait and retry
            }

            delay(POLL_INTERVAL_MS)
        }

        throw IOException("AssemblyAI transcription timed out after $MAX_POLL_ATTEMPTS polls")
    }

    private suspend fun uploadAudio(file: File): String {
        val uploadRequest = Request.Builder()
            .url("$baseUrl/v2/upload")
            .header("Authorization", apiKey)
            .header("Content-Type", "audio/mp4")
            .post(file.asRequestBody("audio/mp4".toMediaType()))
            .build()
        return JSONObject(executeAsync(uploadRequest)).optString("upload_url")
            .also { check(it.isNotBlank()) { "AssemblyAI upload did not return upload_url" } }
    }

    /**
     * Executes an OkHttp [Request] asynchronously and suspends until the response
     * arrives. The OkHttp call is cancelled when the coroutine is cancelled.
     */
    private suspend fun executeAsync(request: Request): String =
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
                        if (!response.isSuccessful) {
                            Log.e(TAG, "HTTP ${response.code} — body: $body")
                            cont.resumeWithException(IOException("AssemblyAI HTTP ${response.code}: $body"))
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

    companion object {
        private const val TAG = "AssemblyAIProvider"

        /** Wait this long before the very first poll (AssemblyAI needs a moment to queue). */
        private const val INITIAL_POLL_MS  = 1_000L

        /** Interval between subsequent polls. */
        private const val POLL_INTERVAL_MS = 1_500L

        /** Hard cap: 60 polls × 1.5 s ≈ 90 s max before giving up. */
        private const val MAX_POLL_ATTEMPTS = 60
    }
}
