package com.echo.dictation.speech.provider

import android.util.Log
import kotlinx.coroutines.delay
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.net.SocketTimeoutException
import java.net.UnknownHostException

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
 * Step 3 – Poll until status = "completed" or "error":
 *   GET /v2/transcript/{id}
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
            .header("Authorization", apiKey)   // no "Bearer" for AssemblyAI
            .header("Content-Type", "application/json")
            .post(jobBody.toRequestBody("application/json".toMediaType()))
            .build()

        val transcriptId = execute(submitRequest).let { json ->
            JSONObject(json).optString("id")
                .also { Log.d(TAG, "Transcript ID: $it") }
        }
        check(transcriptId.isNotBlank()) { "AssemblyAI did not return a transcript ID" }

        // ── Step 3: poll for completion ───────────────────────────────────────
        Log.d(TAG, "Step 3: polling for completion…")
        var attempts = 0
        while (attempts < MAX_POLL_ATTEMPTS) {
            delay(POLL_INTERVAL_MS)
            attempts++
            val pollRequest = Request.Builder()
                .url("$baseUrl/v2/transcript/$transcriptId")
                .header("Authorization", apiKey)
                .get()
                .build()

            val pollJson = execute(pollRequest)
            val status = JSONObject(pollJson).optString("status")
            Log.d(TAG, "Poll #$attempts status=$status")

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
            }
        }
        throw IOException("AssemblyAI transcription timed out after $MAX_POLL_ATTEMPTS polls")
    }

    private fun uploadAudio(file: File): String {
        val uploadRequest = Request.Builder()
            .url("$baseUrl/v2/upload")
            .header("Authorization", apiKey)
            .header("Content-Type", "audio/mp4")
            .post(file.asRequestBody("audio/mp4".toMediaType()))
            .build()
        return JSONObject(execute(uploadRequest)).optString("upload_url")
            .also { check(it.isNotBlank()) { "AssemblyAI upload did not return upload_url" } }
    }

    private fun execute(request: Request): String {
        return try {
            val response = httpClient.newCall(request).execute()
            val body = response.body?.string() ?: ""
            if (!response.isSuccessful) {
                Log.e(TAG, "HTTP ${response.code} — body: $body")
                throw IOException("AssemblyAI HTTP ${response.code}: $body")
            }
            body
        } catch (e: UnknownHostException) { Log.e(TAG, "UnknownHost", e); throw e }
        catch (e: SocketTimeoutException) { Log.e(TAG, "Timeout", e); throw e }
        catch (e: javax.net.ssl.SSLException) { Log.e(TAG, "SSL", e); throw e }
        catch (e: IOException) { Log.e(TAG, "IOException: ${e.message}", e); throw e }
        catch (e: Exception) { Log.e(TAG, "Unexpected: ${e.message}", e); throw e }
    }

    companion object {
        private const val TAG = "AssemblyAIProvider"
        private const val MAX_POLL_ATTEMPTS = 60     // 60 × 2 s = 2 min max
        private const val POLL_INTERVAL_MS  = 2_000L
    }
}
