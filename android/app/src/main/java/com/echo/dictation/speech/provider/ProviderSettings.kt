package com.echo.dictation.speech.provider

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Stores the user's currently selected provider, plus per-provider model and
 * base-URL overrides.
 *
 * These values are not sensitive (no credentials), so plain
 * [android.content.SharedPreferences] is appropriate.
 * Credentials live in [ProviderKeyStore].
 *
 * Per-provider storage keys:
 *   model_{PROVIDER_ID}   — selected model for that provider
 *   url_{PROVIDER_ID}     — custom base URL for that provider
 *
 * The legacy single-slot keys (KEY_MODEL, KEY_BASE_URL) are kept read-only so
 * existing installations silently migrate: the first time a provider is selected
 * after this update its model/URL will fall back to the legacy value (if present)
 * and subsequent saves write to the new per-provider key.
 */
@Singleton
class ProviderSettings @Inject constructor(@ApplicationContext context: Context) {

    private val p = context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)

    // ── Selected provider ─────────────────────────────────────────────────────

    /** Currently selected provider. Defaults to [ProviderId.GROQ]. */
    var selectedProvider: ProviderId
        get() = runCatching {
            ProviderId.valueOf(
                p.getString(KEY_PROVIDER, ProviderId.GROQ.name) ?: ProviderId.GROQ.name
            )
        }.getOrDefault(ProviderId.GROQ)
        set(v) { p.edit().putString(KEY_PROVIDER, v.name).apply() }

    // ── Per-provider model ────────────────────────────────────────────────────

    /**
     * Returns the saved model for [provider], or the provider's first default
     * model when nothing has been saved yet.
     */
    fun getModelForProvider(provider: ProviderId): String {
        // 1. Check per-provider slot
        val perProvider = p.getString(modelKey(provider), null)
        if (!perProvider.isNullOrBlank()) return perProvider

        // 2. Migrate from legacy single-slot (only meaningful for the previously
        //    active provider — harmless to use as a one-time starting value).
        if (provider == selectedProvider) {
            val legacy = p.getString(KEY_MODEL_LEGACY, null)
            if (!legacy.isNullOrBlank()) return legacy
        }

        // 3. Fall back to first model in the registry
        return ProviderRegistry.getConfig(provider).models.firstOrNull() ?: ""
    }

    /**
     * Persist [model] for [provider].
     */
    fun setModelForProvider(provider: ProviderId, model: String) {
        p.edit().putString(modelKey(provider), model).apply()
    }

    /**
     * Convenience accessor: model for the currently selected provider.
     * Backed by [getModelForProvider] / [setModelForProvider].
     */
    var selectedModel: String
        get() = getModelForProvider(selectedProvider)
        set(v) = setModelForProvider(selectedProvider, v)

    // ── Per-provider base URL ─────────────────────────────────────────────────

    /**
     * Returns the saved custom base URL for [provider], or an empty string when
     * none has been saved yet.
     */
    fun getBaseUrlForProvider(provider: ProviderId): String {
        // 1. Check per-provider slot
        val perProvider = p.getString(urlKey(provider), null)
        if (!perProvider.isNullOrBlank()) return perProvider

        // 2. Migrate from legacy single-slot (only for the current provider)
        if (provider == selectedProvider) {
            val legacy = p.getString(KEY_BASE_URL_LEGACY, null)
            if (!legacy.isNullOrBlank()) return legacy
        }

        return ""
    }

    /**
     * Persist [url] for [provider].
     */
    fun setBaseUrlForProvider(provider: ProviderId, url: String) {
        p.edit().apply {
            if (url.isBlank()) remove(urlKey(provider))
            else putString(urlKey(provider), url)
        }.apply()
    }

    /**
     * Convenience accessor: custom base URL for the currently selected provider.
     * Backed by [getBaseUrlForProvider] / [setBaseUrlForProvider].
     */
    var customBaseUrl: String
        get() = getBaseUrlForProvider(selectedProvider)
        set(v) = setBaseUrlForProvider(selectedProvider, v)

    // ── Effective base URL ────────────────────────────────────────────────────

    /**
     * Returns the effective base URL for [provider]:
     * - Fixed-URL providers: returns [ProviderConfig.defaultBaseUrl].
     * - Azure / Custom: returns the user-supplied URL for that provider.
     */
    fun effectiveBaseUrlForProvider(provider: ProviderId): String {
        val config = ProviderRegistry.getConfig(provider)
        return if (config.requiresCustomBaseUrl) getBaseUrlForProvider(provider)
               else config.defaultBaseUrl
    }

    /**
     * Returns the effective base URL for the currently selected provider.
     * Kept for backward compatibility with call-sites that don't pass a provider.
     */
    fun effectiveBaseUrl(): String = effectiveBaseUrlForProvider(selectedProvider)

    // ── Key helpers ───────────────────────────────────────────────────────────

    private fun modelKey(provider: ProviderId) = "model_${provider.name}"
    private fun urlKey(provider: ProviderId)   = "url_${provider.name}"

    companion object {
        private const val PREFS_FILE       = "provider_settings"
        private const val KEY_PROVIDER     = "selected_provider"
        // Legacy single-slot keys — read during migration, never written again
        private const val KEY_MODEL_LEGACY   = "selected_model"
        private const val KEY_BASE_URL_LEGACY = "custom_base_url"
    }
}
