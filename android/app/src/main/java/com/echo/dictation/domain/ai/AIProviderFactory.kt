package com.echo.dictation.domain.ai

import com.echo.dictation.speech.provider.ProviderId

/**
 * Factory that returns the [AIProvider] for the currently selected provider.
 *
 * This is the single point of indirection between the business logic layer and
 * the concrete provider implementations.  The rest of the app never instantiates
 * provider objects directly — it always goes through this factory.
 *
 * Callers receive [AIProvider] which exposes only [AIProvider.generateCompletion].
 * If the active provider does not support text generation, the factory throws
 * [UnsupportedOperationException] with a message that can be shown to the user.
 */
interface AIProviderFactory {
    /**
     * Returns the [AIProvider] for the currently selected speech/AI provider.
     * @throws UnsupportedOperationException if the selected provider has no LLM capability.
     * @throws IllegalStateException if a required API key or endpoint is missing.
     */
    fun getProvider(): AIProvider

    /**
     * Returns the [AIProvider] for a specific [providerId], regardless of the selection.
     * Used when Settings explicitly needs to test a particular provider.
     */
    fun getProvider(providerId: ProviderId): AIProvider

    /** True when the current provider has a configured API key AND supports text generation. */
    fun isCurrentProviderConfiguredForAI(): Boolean

    /**
     * The display name of the provider that will be used for AI features,
     * e.g. "Groq", "OpenAI", "Google Gemini".
     */
    fun currentProviderDisplayName(): String
}
