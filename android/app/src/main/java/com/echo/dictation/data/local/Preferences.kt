package com.echo.dictation.data.local

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class TokenStore @Inject constructor(@ApplicationContext context: Context) {
    private val prefs: SharedPreferences = runCatching { val key = MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(); EncryptedSharedPreferences.create(context, "auth", key, EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV, EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM) }.getOrElse { context.getSharedPreferences("auth_fallback", Context.MODE_PRIVATE) }
    var token: String? get() = prefs.getString("token", null); set(value) { prefs.edit().putString("token", value).apply() }
    var email: String? get() = prefs.getString("email", null); set(value) { prefs.edit().putString("email", value).apply() }
    fun clear() { prefs.edit().clear().apply() }
}
@Singleton
class AppPreferences @Inject constructor(@ApplicationContext context: Context) {
    private val p = context.getSharedPreferences("settings", Context.MODE_PRIVATE)
    var language: String get() = p.getString("language", "en") ?: "en"; set(v) { p.edit().putString("language", v).apply() }
    var model: String get() = p.getString("model", "whisper-large-v3-turbo") ?: "whisper-large-v3-turbo"; set(v) { p.edit().putString("model", v).apply() }
    var retention: Int get() = p.getInt("retention", 30); set(v) { p.edit().putInt("retention", v).apply() }
    var grammar: Boolean get() = p.getBoolean("grammar", true); set(v) { p.edit().putBoolean("grammar", v).apply() }
    var theme: String get() = p.getString("theme", "system") ?: "system"; set(v) { p.edit().putString("theme", v).apply() }
    var autoStart: Boolean get() = p.getBoolean("auto_start", false); set(v) { p.edit().putBoolean("auto_start", v).apply() }
    var floatingPillX: Int get() = p.getInt("floating_pill_x", Int.MIN_VALUE); set(v) { p.edit().putInt("floating_pill_x", v).apply() }
    var floatingPillY: Int get() = p.getInt("floating_pill_y", Int.MIN_VALUE); set(v) { p.edit().putInt("floating_pill_y", v).apply() }
}
