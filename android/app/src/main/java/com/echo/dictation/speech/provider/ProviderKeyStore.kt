package com.echo.dictation.speech.provider

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Encrypted, per-provider credential store.
 *
 * Backed by [EncryptedSharedPreferences] (AES-256-GCM / AES-256-SIV via Android Keystore).
 * Falls back to plain [SharedPreferences] if the Keystore is unavailable so the app
 * never crashes on restricted hardware or emulators.
 *
 * Keys are stored with the prefix "key_{PROVIDER_ID}".
 * Custom base-URL overrides are stored with the prefix "url_{PROVIDER_ID}".
 *
 * SECURITY: API keys are never logged. The TAG constant used in log calls must
 * never appear adjacent to a key value.
 */
@Singleton
class ProviderKeyStore @Inject constructor(@ApplicationContext private val context: Context) {

    private val prefs: SharedPreferences = runCatching {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context,
            PREFS_FILE,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }.getOrElse { ex ->
        Log.w(TAG, "EncryptedSharedPreferences unavailable — using plain storage", ex)
        context.getSharedPreferences("${PREFS_FILE}_fallback", Context.MODE_PRIVATE)
    }

    // ── API keys ──────────────────────────────────────────────────────────────

    /** Returns the stored API key for [provider], or null if none is saved. */
    fun getKey(provider: ProviderId): String? =
        prefs.getString(keyPref(provider), null)?.takeIf { it.isNotBlank() }

    /**
     * Persist [key] for [provider].
     * Pass a blank / empty string to remove the key (equivalent to [clearKey]).
     */
    fun setKey(provider: ProviderId, key: String) {
        prefs.edit().apply {
            if (key.isBlank()) remove(keyPref(provider))
            else putString(keyPref(provider), key)
        }.apply()
    }

    /** Remove the stored key for [provider]. */
    fun clearKey(provider: ProviderId) {
        prefs.edit().remove(keyPref(provider)).apply()
    }

    /** True if a non-blank key has been stored for [provider]. */
    fun isConfigured(provider: ProviderId): Boolean = !getKey(provider).isNullOrBlank()

    // ── Base URL overrides (Azure / Custom providers) ─────────────────────────

    /** Returns a user-supplied base URL override for [provider], or null. */
    fun getBaseUrl(provider: ProviderId): String? =
        prefs.getString(urlPref(provider), null)?.takeIf { it.isNotBlank() }

    /** Persist a custom base URL for [provider]. */
    fun setBaseUrl(provider: ProviderId, url: String) {
        prefs.edit().apply {
            if (url.isBlank()) remove(urlPref(provider))
            else putString(urlPref(provider), url)
        }.apply()
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun keyPref(provider: ProviderId) = "key_${provider.name}"
    private fun urlPref(provider: ProviderId) = "url_${provider.name}"

    companion object {
        private const val TAG = "ProviderKeyStore"
        private const val PREFS_FILE = "provider_credentials"
    }
}
