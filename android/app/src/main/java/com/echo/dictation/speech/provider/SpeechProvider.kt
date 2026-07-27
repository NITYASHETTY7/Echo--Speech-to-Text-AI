package com.echo.dictation.speech.provider

import java.io.File

// ─── Provider identity ───────────────────────────────────────────────────────

enum class ProviderId {
    GROQ, OPENAI, OPENROUTER, DEEPGRAM, ASSEMBLYAI, GEMINI, AZURE, BEDROCK, CUSTOM;

    val displayName: String get() = when (this) {
        GROQ       -> "Groq"
        OPENAI     -> "OpenAI"
        OPENROUTER -> "OpenRouter"
        DEEPGRAM   -> "Deepgram"
        ASSEMBLYAI -> "AssemblyAI"
        GEMINI     -> "Google Gemini"
        AZURE      -> "Azure OpenAI"
        BEDROCK    -> "AWS Bedrock"
        CUSTOM     -> "Custom OpenAI-Compatible"
    }
}

// ─── Provider configuration ──────────────────────────────────────────────────

/**
 * Static, per-provider configuration that never changes at runtime.
 * Credentials and user overrides live in [ProviderKeyStore] / [ProviderSettings].
 */
data class ProviderConfig(
    val id: ProviderId,
    val displayName: String,
    /** Default base URL. Empty string means the user must supply one. */
    val defaultBaseUrl: String,
    /** Pre-defined model list. Empty list means the user enters the model manually. */
    val models: List<String>,
    /** True when the user must supply the base URL (Azure, Custom). */
    val requiresCustomBaseUrl: Boolean = false,
    /** True when the user must type the model name (Azure, Custom). */
    val requiresCustomModel: Boolean = false,
    /**
     * HTTP header name for authentication, e.g. "Authorization" or "api-key".
     * The value is formatted using [authValueFormat] with the API key substituted for %s.
     */
    val authHeaderName: String = "Authorization",
    /** Format string for the header value. %s is replaced with the API key. */
    val authValueFormat: String = "Bearer %s",
)

// ─── Transcription result ────────────────────────────────────────────────────

data class TranscriptionResult(val text: String)

// ─── Provider interface ──────────────────────────────────────────────────────

/**
 * Common interface implemented by every speech provider.
 *
 * The rest of the application interacts with transcription exclusively through
 * this interface. Adding a new provider is a matter of creating a new class that
 * implements [SpeechProvider] — no changes to the call-sites required.
 */
interface SpeechProvider {
    val config: ProviderConfig

    /**
     * Transcribe [audioFile] (MPEG-4 AAC, produced by [AudioRecorder]).
     *
     * @param audioFile  The local audio file to transcribe.
     * @param model      The model identifier string for this provider.
     * @param language   ISO-639-1 language code, or null for auto-detection.
     * @return [TranscriptionResult] with trimmed transcript text.
     *         Empty [TranscriptionResult.text] indicates silence / hallucination.
     * @throws Exception on any network or API error — callers display the message.
     */
    suspend fun transcribe(audioFile: File, model: String, language: String?): TranscriptionResult
}
