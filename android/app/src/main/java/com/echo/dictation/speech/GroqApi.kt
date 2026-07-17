package com.echo.dictation.speech

import com.google.gson.annotations.SerializedName
import okhttp3.MultipartBody
import okhttp3.RequestBody
import retrofit2.http.Multipart
import retrofit2.http.POST
import retrofit2.http.Part

/**
 * Groq audio transcription response.
 *
 * Groq's verbose_json format returns the full transcript in [text] plus optional
 * [segments] for timed word/sentence boundaries. Only [text] is used by the app;
 * the rest is present so the model survives forward-compatible API changes.
 */
data class GroqTranscriptionResponse(
    val text: String,
    val duration: Double? = null,
    val segments: List<GroqSegment>? = null,
    val language: String? = null,
)

data class GroqSegment(
    val id: Int = 0,
    val start: Double = 0.0,
    val end: Double = 0.0,
    val text: String = "",
    @SerializedName("no_speech_prob") val noSpeechProb: Double = 0.0,
)

/**
 * Retrofit interface for the single Groq endpoint this app uses.
 *
 * Base URL: https://api.groq.com/openai/v1/
 * Auth:     "Authorization: Bearer <key>" injected by [GroqApiKeyInterceptor].
 *
 * Groq's speech endpoint is identical to OpenAI's /v1/audio/transcriptions so
 * the same multipart form layout is used:
 *   - file     : the audio file bytes (m4a/mp4)
 *   - model    : e.g. "whisper-large-v3-turbo"
 *   - language : ISO-639-1 code (optional; omit for auto-detect)
 *   - response_format : "verbose_json" to get segments + duration
 *   - temperature : 0 for deterministic output
 *   - prompt  : domain-specific hint to improve accuracy
 */
interface GroqApi {
    @Multipart
    @POST("audio/transcriptions")
    suspend fun transcribe(
        @Part file: MultipartBody.Part,
        @Part("model") model: RequestBody,
        @Part("response_format") responseFormat: RequestBody,
        @Part("temperature") temperature: RequestBody,
        @Part("prompt") prompt: RequestBody,
        @Part("language") language: RequestBody? = null,
    ): GroqTranscriptionResponse
}
