package com.echo.dictation.data.local

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

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
