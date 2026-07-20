package com.echo.dictation.speech.provider

import android.util.Base64
import android.util.Log
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.net.SocketTimeoutException
import java.net.UnknownHostException

/**
 * Google Gemini speech transcription.
 *
 * Sends the audio file as a base64-encoded inline part in a generateContent request.
 *
 * POST /v1beta/models/{model}:generateContent
 * Header: x-goog-api-key: {apiKey}
 * Body:
 * {
 *   "contents": [{
 *     "parts": [
 *       { "text": "Transcribe this audio exactly." },
 *       { "inline_data": { "mime_type": "audio/mp4", "data": "<base64>" } }
 *     ]
 *   }]
 * }
 *
 * Response: candidates[0].content.parts[0].text
 *
 * Note: Gemini file size limits apply (~20 MB inline). The AudioRecorder produces
 * short recordings well within this limit.
 */
class GeminiProvider(
    override val config: ProviderConfig,
    private val apiKey: String,
    private val httpClient: OkHttpClient,
) : SpeechProvider {

    private val baseUrl = config.defaultBaseUrl.trimEnd('/')

    override suspend fun transcribe(audioFile: File, model: String, language: String?): TranscriptionResult {
        require(audioFile.exists() && audioFile.length() > 0) { "Audio file is empty or missing" }

        Log.d(TAG, "=== GEMINI TRANSCRIBE START ===")
        Log.d(TAG, "model: $model  file: ${audioFile.name}  size=${audioFile.length()}B")

        val audioBytes = audioFile.readBytes()
        val base64Audio = Base64.encodeToString(audioBytes, Base64.NO_WRAP)

        val prompt = buildString {
            append("Transcribe the following audio exactly. ")
            if (!language.isNullOrBlank() && language.lowercase() != "auto") {
                append("The audio is in $language. ")
            }
            append("Return only the transcript text with no additional commentary.")
        }

        val requestJson = JSONObject().apply {
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

        val url = "$baseUrl/v1beta/models/$model:generateContent"
        Log.d(TAG, "POST $url")

        val request = Request.Builder()
            .url(url)
            .header("x-goog-api-key", apiKey)
            .header("Content-Type", "application/json")
            .post(requestJson.toRequestBody("application/json".toMediaType()))
            .build()

        val responseBody = try {
            val response = httpClient.newCall(request).execute()
            val body = response.body?.string() ?: ""
            Log.d(TAG, "HTTP ${response.code}")
            if (!response.isSuccessful) {
                Log.e(TAG, "HTTP ${response.code} — body: $body")
                throw IOException("Gemini HTTP ${response.code}: $body")
            }
            body
        } catch (e: UnknownHostException) { Log.e(TAG, "UnknownHost", e); throw e }
        catch (e: SocketTimeoutException) { Log.e(TAG, "Timeout", e); throw e }
        catch (e: javax.net.ssl.SSLException) { Log.e(TAG, "SSL", e); throw e }
        catch (e: IOException) { Log.e(TAG, "IOException: ${e.message}", e); throw e }
        catch (e: Exception) { Log.e(TAG, "Unexpected: ${e.message}", e); throw e }

        val text = parseResponse(responseBody)
        Log.d(TAG, "transcript: \"${text.take(200)}\"")
        Log.d(TAG, "=== GEMINI TRANSCRIBE DONE ===")
        return TranscriptionResult(text)
    }

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
        Log.e(TAG, "Failed to parse Gemini response: ${e.message}")
        ""
    }

    companion object {
        private const val TAG = "GeminiProvider"
    }
}
