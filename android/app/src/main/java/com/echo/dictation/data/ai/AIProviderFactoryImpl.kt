package com.echo.dictation.data.ai

import android.util.Log
import com.echo.dictation.domain.ai.AIProvider
import com.echo.dictation.domain.ai.AIProviderFactory
import com.echo.dictation.speech.provider.ProviderId
import com.echo.dictation.speech.provider.ProviderKeyStore
import com.echo.dictation.speech.provider.ProviderRegistry
import com.echo.dictation.speech.provider.ProviderSettings
import okhttp3.OkHttpClient
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Concrete [AIProviderFactory].
 *
 * Reads [ProviderSettings.selectedProvider] at call-time (not construction-time)
 * so a provider switch in Settings takes effect immediately without restarting
 * or re-injecting anything.
 *
 * Provider ↔ AI capability map:
 * ┌──────────────┬──────────────────────────────────────────────────────────────┐
 * │ Provider     │ AI backend used                                               │
 * ├──────────────┼──────────────────────────────────────────────────────────────┤
 * │ GROQ         │ Groq Chat Completions (llama-3.3-70b-versatile default)       │
 * │ OPENAI       │ OpenAI Chat Completions (gpt-4.1 default)                     │
 * │ OPENROUTER   │ OpenRouter Chat Completions (user-selected model)             │
 * │ GEMINI       │ Google Gemini REST API (model resolved dynamically via GeminiModelResolver) │
 * │ AZURE        │ Azure OpenAI Chat Completions (user-configured deployment)    │
 * │ BEDROCK      │ AWS Bedrock Converse API (user-selected model)                │
 * │ CUSTOM       │ OpenAI-Compatible endpoint (user-configured)                  │
 * │ DEEPGRAM     │ No LLM support → throws UnsupportedOperationException        │
 * │ ASSEMBLYAI   │ No LLM support → throws UnsupportedOperationException        │
 * └──────────────┴──────────────────────────────────────────────────────────────┘
 */
@Singleton
class AIProviderFactoryImpl @Inject constructor(
    private val keyStore: ProviderKeyStore,
    private val settings: ProviderSettings,
    private val httpClient: OkHttpClient,
    private val modelResolver: com.echo.dictation.speech.provider.GeminiModelResolver,
) : AIProviderFactory {

    // ── Public API ────────────────────────────────────────────────────────────

    override fun getProvider(): AIProvider = buildProvider(settings.selectedProvider)

    override fun getProvider(providerId: ProviderId): AIProvider = buildProvider(providerId)

    override fun isCurrentProviderConfiguredForAI(): Boolean {
        val provider = settings.selectedProvider
        if (!supportsAI(provider)) return false
        return keyStore.isConfigured(provider)
    }

    override fun currentProviderDisplayName(): String =
        ProviderRegistry.getConfig(settings.selectedProvider).displayName

    // ── Builder ───────────────────────────────────────────────────────────────

    private fun buildProvider(providerId: ProviderId): AIProvider {
        Log.d(TAG, "buildProvider($providerId)")

        if (!supportsAI(providerId)) {
            val name = ProviderRegistry.getConfig(providerId).displayName
            throw UnsupportedOperationException(
                "$name does not support AI text generation. " +
                "Please select a different AI provider in Settings, or configure a " +
                "separate AI provider for text features."
            )
        }

        val apiKey = keyStore.getKey(providerId)
            ?: throw IllegalStateException(
                "No API key configured for ${ProviderRegistry.getConfig(providerId).displayName}. " +
                "Open Echo → Settings to add your key."
            )

        return when (providerId) {
            ProviderId.GROQ     -> GroqAIProvider(keyStore, httpClient)

            ProviderId.OPENAI   -> OpenAICompatibleAIProvider(
                id          = "openai",
                name        = "OpenAI",
                defaultModel = "gpt-4.1",
                baseUrl     = "https://api.openai.com/v1/",
                apiKey      = apiKey,
                httpClient  = httpClient,
            )

            ProviderId.OPENROUTER -> OpenAICompatibleAIProvider(
                id          = "openrouter",
                name        = "OpenRouter",
                defaultModel = settings.selectedModel.ifBlank { "openai/gpt-4.1" },
                baseUrl     = "https://openrouter.ai/api/v1/",
                apiKey      = apiKey,
                httpClient  = httpClient,
                extraHeaders = mapOf(
                    "HTTP-Referer" to "https://echo.dictation.app",
                    "X-Title"     to "Echo Dictation",
                ),
            )

            ProviderId.GEMINI   -> GeminiAIProvider(
                apiKey        = apiKey,
                httpClient    = httpClient,
                modelResolver = modelResolver,
            )

            ProviderId.AZURE    -> {
                val baseUrl = settings.customBaseUrl.ifBlank {
                    keyStore.getBaseUrl(providerId) ?: ""
                }
                check(baseUrl.isNotBlank()) {
                    "Azure OpenAI requires a deployment endpoint URL. Open Echo → Settings to configure."
                }
                OpenAICompatibleAIProvider(
                    id          = "azure",
                    name        = "Azure OpenAI",
                    defaultModel = settings.selectedModel.ifBlank { "gpt-4" },
                    baseUrl     = baseUrl,
                    apiKey      = apiKey,
                    httpClient  = httpClient,
                    authHeaderName = "api-key",
                    authValueFormat = "%s",
                )
            }

            ProviderId.BEDROCK  -> BedrockAIProvider(
                credentialsRaw = apiKey,
                model          = settings.selectedModel.ifBlank { "anthropic.claude-3-5-sonnet-20241022-v2:0" },
                httpClient     = httpClient,
            )

            ProviderId.CUSTOM   -> {
                val baseUrl = settings.customBaseUrl.ifBlank {
                    keyStore.getBaseUrl(providerId) ?: ""
                }
                check(baseUrl.isNotBlank()) {
                    "Custom endpoint requires a Base URL. Open Echo → Settings to configure."
                }
                OpenAICompatibleAIProvider(
                    id          = "custom",
                    name        = "Custom",
                    defaultModel = settings.selectedModel.ifBlank { "default" },
                    baseUrl     = baseUrl,
                    apiKey      = apiKey,
                    httpClient  = httpClient,
                )
            }

            // These providers have no LLM — guarded above, but Kotlin requires exhaustive when
            ProviderId.DEEPGRAM, ProviderId.ASSEMBLYAI -> throw UnsupportedOperationException(
                "${ProviderRegistry.getConfig(providerId).displayName} does not support AI text generation."
            )
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun supportsAI(providerId: ProviderId): Boolean = when (providerId) {
        ProviderId.DEEPGRAM,
        ProviderId.ASSEMBLYAI -> false
        else                  -> true
    }

    companion object {
        private const val TAG = "AIProviderFactory"
    }
}
