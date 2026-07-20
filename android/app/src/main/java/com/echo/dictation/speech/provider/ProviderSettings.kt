package com.echo.dictation.speech.provider

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Stores the user's currently selected provider and model.
 *
 * These values are not sensitive (no credentials), so plain [android.content.SharedPreferences]
 * is appropriate. Credentials live in [ProviderKeyStore].
 */
@Singleton
class ProviderSettings @Inject constructor(@ApplicationContext context: Context) {

    private val p = context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)

    /** Currently selected provider. Defaults to [ProviderId.GROQ]. */
    var selectedProvider: ProviderId
        get() = runCatching {
            ProviderId.valueOf(p.getString(KEY_PROVIDER, ProviderId.GROQ.name) ?: ProviderId.GROQ.name)
        }.getOrDefault(ProviderId.GROQ)
        set(v) { p.edit().putString(KEY_PROVIDER, v.name).apply() }

    /**
     * Currently selected model for the active provider.
     * Defaults to the first model in the provider's config list when not set.
     */
    var selectedModel: String
        get() {
            val stored = p.getString(KEY_MODEL, null)
            if (!stored.isNullOrBlank()) return stored
            // Fall back to first model in registry for current provider
            val models = ProviderRegistry.getConfig(selectedProvider).models
            return models.firstOrNull() ?: ""
        }
        set(v) { p.edit().putString(KEY_MODEL, v).apply() }

    /**
     * User-supplied base URL — used for AZURE and CUSTOM providers.
     * Stored here in plain prefs (not sensitive — it's just a URL).
     */
    var customBaseUrl: String
        get() = p.getString(KEY_BASE_URL, "") ?: ""
        set(v) { p.edit().putString(KEY_BASE_URL, v).apply() }

    /**
     * Returns the effective base URL for the current provider:
     * - For providers with a fixed URL: returns [ProviderConfig.defaultBaseUrl].
     * - For Azure/Custom: returns [customBaseUrl] (user-supplied).
     */
    fun effectiveBaseUrl(): String {
        val config = ProviderRegistry.getConfig(selectedProvider)
        return if (config.requiresCustomBaseUrl) customBaseUrl else config.defaultBaseUrl
    }

    companion object {
        private const val PREFS_FILE  = "provider_settings"
        private const val KEY_PROVIDER = "selected_provider"
        private const val KEY_MODEL    = "selected_model"
        private const val KEY_BASE_URL = "custom_base_url"
    }
}
