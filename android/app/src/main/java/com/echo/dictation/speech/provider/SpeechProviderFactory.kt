package com.echo.dictation.speech.provider

import android.util.Log
import okhttp3.OkHttpClient
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SpeechProviderFactory @Inject constructor(
    private val keyStore: ProviderKeyStore,
    private val settings: ProviderSettings,
    private val httpClient: OkHttpClient,
) {
    fun getProvider(): SpeechProvider {
        val providerId = settings.selectedProvider
        val config     = ProviderRegistry.getConfig(providerId)

        Log.d(TAG, "getProvider() — providerId=$providerId  displayName=${config.displayName}")

        val apiKey = keyStore.getKey(providerId)
        Log.d(TAG, "apiKey present=${apiKey != null}  length=${apiKey?.length ?: 0}")

        if (apiKey == null) {
            Log.e(TAG, "NO API KEY for $providerId — throwing IllegalStateException")
            throw IllegalStateException(
                "No API key configured for ${config.displayName}. Open Echo → Settings to add your key."
            )
        }

        val baseUrl = if (config.requiresCustomBaseUrl) {
            val url = settings.customBaseUrl.ifBlank { keyStore.getBaseUrl(providerId) ?: "" }
            Log.d(TAG, "customBaseUrl='$url'")
            check(url.isNotBlank()) {
                "${config.displayName} requires a Base URL. Open Echo → Settings to configure."
            }
            url
        } else {
            config.defaultBaseUrl.also { Log.d(TAG, "defaultBaseUrl='$it'") }
        }

        val provider: SpeechProvider = when (providerId) {
            ProviderId.DEEPGRAM   -> DeepgramProvider(config, apiKey, httpClient)
            ProviderId.ASSEMBLYAI -> AssemblyAIProvider(config, apiKey, httpClient)
            ProviderId.GEMINI     -> GeminiProvider(config, apiKey, httpClient)
            // BEDROCK uses OpenAI-compatible API; baseUrl is the region endpoint
            // supplied by the user. Falls through to OpenAICompatibleProvider.
            else                  -> OpenAICompatibleProvider(config, apiKey, baseUrl, httpClient)
        }

        Log.d(TAG, "returning ${provider::class.java.simpleName} for $providerId")
        return provider
    }

    fun isCurrentProviderConfigured(): Boolean {
        val provider = settings.selectedProvider
        val configured = keyStore.isConfigured(provider)
        Log.d(TAG, "isCurrentProviderConfigured() provider=$provider configured=$configured")
        return configured
    }

    companion object {
        private const val TAG = "SpeechProviderFactory"
    }
}
