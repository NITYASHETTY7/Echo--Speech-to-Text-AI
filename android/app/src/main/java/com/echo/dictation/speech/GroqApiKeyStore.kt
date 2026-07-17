package com.echo.dictation.speech

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Encrypted, device-local store for the user's Groq API key.
 *
 * Uses [EncryptedSharedPreferences] backed by an AES-256-GCM [MasterKey] from
 * the Android Keystore, the same mechanism the app already uses for auth tokens.
 * Falls back to plain SharedPreferences if the keystore is unavailable
 * (e.g. emulators without secure hardware) so the app never crashes on key
 * storage failure.
 *
 * The key is written once from the Settings screen and read on every transcription
 * request via [GroqApiKeyInterceptor].
 */
@Singleton
class GroqApiKeyStore @Inject constructor(@ApplicationContext context: Context) {

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
    }.getOrElse {
        android.util.Log.w(TAG, "EncryptedSharedPreferences unavailable, using plain storage", it)
        context.getSharedPreferences(PREFS_FILE + "_fallback", Context.MODE_PRIVATE)
    }

    /** The stored Groq API key, or null if none has been saved yet. */
    var apiKey: String?
        get() = prefs.getString(KEY_API_KEY, null)?.takeIf { it.isNotBlank() }
        set(value) {
            prefs.edit().apply {
                if (value.isNullOrBlank()) remove(KEY_API_KEY) else putString(KEY_API_KEY, value)
            }.apply()
        }

    /** True when an API key has been stored. */
    val isConfigured: Boolean get() = !apiKey.isNullOrBlank()

    /** Wipe the stored key (e.g. on sign-out or key reset). */
    fun clear() = prefs.edit().remove(KEY_API_KEY).apply()

    companion object {
        private const val TAG = "GroqApiKeyStore"
        private const val PREFS_FILE = "groq_credentials"
        private const val KEY_API_KEY = "api_key"
    }
}
