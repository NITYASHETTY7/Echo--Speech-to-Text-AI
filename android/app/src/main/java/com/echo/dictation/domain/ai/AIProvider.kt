package com.echo.dictation.domain.ai

/**
 * Interface contract for pluggable LLM providers.
 *
 * Every provider that can perform AI text generation (grammar correction, rewrite,
 * summarisation, translation, etc.) implements this interface.
 *
 * Providers that ONLY do speech-to-text implement [com.echo.dictation.speech.provider.SpeechProvider].
 * Providers that support BOTH implement this interface AND [com.echo.dictation.speech.provider.SpeechProvider]
 * independently; the [com.echo.dictation.speech.provider.SpeechProviderFactory] and
 * [AIProviderFactory] each return the right interface for the requested capability.
 */
interface AIProvider {
    /** Stable machine-readable identifier, e.g. "groq", "openai", "gemini". */
    val id: String

    /** Human-readable display name shown in the UI. */
    val name: String

    /** The default chat/completion model for this provider. */
    val defaultModel: String

    /**
     * Generate a text completion.
     *
     * @param systemPrompt  Optional system instruction (null → provider omits it).
     * @param userPrompt    The user turn / source text.
     * @param modelOverride Override the default model for this call only.
     * @return The generated text on success, or a typed [AIError] on failure.
     */
    suspend fun generateCompletion(
        systemPrompt: String?,
        userPrompt: String,
        modelOverride: String? = null
    ): Result<String>
}
