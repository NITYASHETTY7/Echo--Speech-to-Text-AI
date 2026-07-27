package com.echo.dictation.speech.provider

/**
 * Central registry of all supported speech providers.
 *
 * Adding a new provider is a two-step change:
 *   1. Add an entry to [ProviderId] enum in SpeechProvider.kt.
 *   2. Add a [ProviderConfig] entry here.
 *
 * No UI code or repository code needs to change.
 */
object ProviderRegistry {

    val allConfigs: List<ProviderConfig> = listOf(
        ProviderConfig(
            id             = ProviderId.GROQ,
            displayName    = "Groq",
            defaultBaseUrl = "https://api.groq.com/openai/v1/",
            models         = listOf("whisper-large-v3-turbo", "whisper-large-v3"),
            authHeaderName = "Authorization",
            authValueFormat = "Bearer %s",
        ),
        ProviderConfig(
            id             = ProviderId.OPENAI,
            displayName    = "OpenAI",
            defaultBaseUrl = "https://api.openai.com/v1/",
            models         = listOf("whisper-1", "gpt-4o-transcribe", "gpt-4o-mini-transcribe"),
            authHeaderName = "Authorization",
            authValueFormat = "Bearer %s",
        ),
        ProviderConfig(
            id             = ProviderId.OPENROUTER,
            displayName    = "OpenRouter",
            defaultBaseUrl = "https://openrouter.ai/api/v1/",
            models         = listOf("openai/whisper-large-v3", "openai/whisper"),
            authHeaderName = "Authorization",
            authValueFormat = "Bearer %s",
        ),
        ProviderConfig(
            id             = ProviderId.DEEPGRAM,
            displayName    = "Deepgram",
            defaultBaseUrl = "https://api.deepgram.com/",
            models         = listOf("nova-3", "nova-2"),
            authHeaderName = "Authorization",
            authValueFormat = "Token %s",
        ),
        ProviderConfig(
            id             = ProviderId.ASSEMBLYAI,
            displayName    = "AssemblyAI",
            defaultBaseUrl = "https://api.assemblyai.com/",
            models         = listOf("default"),
            authHeaderName = "Authorization",
            authValueFormat = "%s",           // no "Bearer" prefix for AssemblyAI
        ),
        ProviderConfig(
            id             = ProviderId.GEMINI,
            displayName    = "Google Gemini",
            defaultBaseUrl = "https://generativelanguage.googleapis.com/",
            models         = listOf("gemini-2.0-flash", "gemini-1.5-flash"),
            authHeaderName = "x-goog-api-key",
            authValueFormat = "%s",           // header value IS the key directly
        ),
        ProviderConfig(
            id                    = ProviderId.AZURE,
            displayName           = "Azure OpenAI",
            defaultBaseUrl        = "",        // user must supply the deployment endpoint
            models                = emptyList(),
            requiresCustomBaseUrl = true,
            requiresCustomModel   = true,
            authHeaderName        = "api-key",
            authValueFormat       = "%s",
        ),
        ProviderConfig(
            id                    = ProviderId.BEDROCK,
            displayName           = "AWS Bedrock",
            // Base URL is region-specific: https://bedrock-runtime.<region>.amazonaws.com/
            // The user must supply their region endpoint in the custom URL field.
            defaultBaseUrl        = "",
            models                = listOf(
                "amazon.nova-lite-v1:0",
                "amazon.nova-pro-v1:0",
                "anthropic.claude-3-5-sonnet-20241022-v2:0",
                "anthropic.claude-3-7-sonnet-20250219-v1:0",
                "anthropic.claude-sonnet-4-5",
                "anthropic.claude-opus-4-5",
                "meta.llama3-3-70b-instruct-v1:0",
                "mistral.mistral-large-2402-v1:0",
            ),
            requiresCustomBaseUrl = true,
            requiresCustomModel   = false,
            // Bedrock uses AWS SigV4 auth. The API key field stores
            // "ACCESS_KEY_ID:SECRET_ACCESS_KEY" and the provider handles signing.
            authHeaderName        = "Authorization",
            authValueFormat       = "Bearer %s",
        ),
        ProviderConfig(
            id                    = ProviderId.CUSTOM,
            displayName          = "Custom OpenAI-Compatible",
            defaultBaseUrl       = "",        // user must supply
            models               = emptyList(),
            requiresCustomBaseUrl = true,
            requiresCustomModel  = true,
            authHeaderName       = "Authorization",
            authValueFormat      = "Bearer %s",
        ),
    )

    /** Convenience map for O(1) lookup. */
    private val configById: Map<ProviderId, ProviderConfig> =
        allConfigs.associateBy { it.id }

    fun getConfig(id: ProviderId): ProviderConfig =
        configById[id] ?: error("No config registered for provider: $id")
}
