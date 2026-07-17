package com.echo.dictation.speech

import android.util.Log
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Thin wrapper around [GroqApi] that mirrors what the Flask backend's
 * /api/transcribe endpoint did:
 *
 *  1. Accept a local audio [File] and a model name.
 *  2. Send the file as a multipart POST to Groq's transcription endpoint.
 *  3. Return the raw transcript text on success.
 *
 * Persistence (Room) is the caller's responsibility. This class is purely
 * about the network call so it stays testable in isolation.
 */
@Singleton
class GroqTranscriptionService @Inject constructor(private val api: GroqApi) {

    /**
     * Transcribe [file] with the given Whisper [model].
     *
     * [language] is an ISO-639-1 code (e.g. "en"). Pass null or "auto" to let
     * Groq auto-detect, identical to the backend's "auto" behaviour.
     *
     * Returns the trimmed transcript string, or throws on error.
     */
    suspend fun transcribe(
        file: File,
        model: String,
        language: String? = null,
    ): String {
        require(file.exists() && file.length() > 0) { "Audio file is empty or missing" }

        Log.d(TAG, "transcribe() -> ${file.name}  model=$model  size=${file.length()}B")

        // Groq accepts m4a (MPEG-4 AAC) - the format AudioRecorder produces.
        val filePart = MultipartBody.Part.createFormData(
            name = "file",
            filename = file.name,
            body = file.asRequestBody("audio/mp4".toMediaType()),
        )

        val modelPart = model.toRequestBody("text/plain".toMediaType())
        val formatPart = "verbose_json".toRequestBody("text/plain".toMediaType())
        val temperaturePart = "0".toRequestBody("text/plain".toMediaType())
        val promptPart = TRANSCRIBE_PROMPT.toRequestBody("text/plain".toMediaType())

        // Only attach the language field when it is a concrete code (not auto/null).
        val languagePart = language
            ?.takeIf { it.isNotBlank() && it.lowercase() != "auto" }
            ?.toRequestBody("text/plain".toMediaType())

        val response = api.transcribe(
            file = filePart,
            model = modelPart,
            responseFormat = formatPart,
            temperature = temperaturePart,
            prompt = promptPart,
            language = languagePart,
        )

        val text = response.text.trim()
        Log.d(TAG, "transcribe() <- ${text.length} chars  duration=${response.duration}s")

        // ── Hallucination guard ───────────────────────────────────────────────
        // Whisper hallucinates filler text ("Thank you.", "you", ".") on silence
        // or very quiet audio that slips past the amplitude gate.
        // verbose_json gives us per-segment no_speech_prob.
        // We discard if ANY segment has high no_speech_prob, or if the average is high.
        // This is stricter than averaging alone, which can be diluted by one good segment.
        val segments = response.segments
        if (!segments.isNullOrEmpty()) {
            val avgNoSpeech = segments.map { it.noSpeechProb }.average()
            val maxNoSpeech = segments.maxOf { it.noSpeechProb }
            Log.d(TAG, "no_speech_prob: avg=${"%.3f".format(avgNoSpeech)} max=${"%.3f".format(maxNoSpeech)}  segments=${segments.size}")
            if (avgNoSpeech >= NO_SPEECH_AVG_THRESHOLD || maxNoSpeech >= NO_SPEECH_MAX_THRESHOLD) {
                Log.w(TAG, "Discarding hallucination (avg=${"%.3f".format(avgNoSpeech)} max=${"%.3f".format(maxNoSpeech)}): \"$text\"")
                return ""
            }
        }

        // ── Known hallucination phrases ───────────────────────────────────────
        // Whisper produces these exact strings on silence regardless of no_speech_prob.
        if (text.lowercase() in HALLUCINATION_PHRASES) {
            Log.w(TAG, "Discarding known hallucination phrase: \"$text\"")
            return ""
        }

        return text
    }

    companion object {
        private const val TAG = "GroqTranscriptionService"

        /**
         * Average no_speech_prob threshold across all segments.
         * Whisper's own internal cutoff is 0.6 — we match it.
         */
        private const val NO_SPEECH_AVG_THRESHOLD = 0.6

        /**
         * If any single segment has no_speech_prob above this, discard entirely.
         * Catches cases where one bad segment drags down an otherwise passing average.
         */
        private const val NO_SPEECH_MAX_THRESHOLD = 0.8

        /**
         * Exact phrases Whisper commonly hallucinates on silence or noise.
         * Checked case-insensitively after trimming.
         */
        private val HALLUCINATION_PHRASES = setOf(
            "you", "thank you.", "thank you", "thanks.", "thanks",
            ".", "..", "...", "bye.", "bye",
            "subtitles by", "subtitles by the amara.org community",
        )

        /**
         * Minimal prompt that suppresses hallucination rather than seeding it.
         * A long domain-specific prompt causes Whisper to "complete" it when
         * it hears silence, generating filler text. A short, neutral prompt
         * avoids that while still cueing proper punctuation.
         */
        private const val TRANSCRIBE_PROMPT = "Echo."
    }
}
