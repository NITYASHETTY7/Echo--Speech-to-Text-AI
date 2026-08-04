package com.echo.dictation.data.local

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AppPreferences @Inject constructor(@ApplicationContext context: Context) {
    private val p = context.getSharedPreferences("settings", Context.MODE_PRIVATE)

    var language: String get() = p.getString("language", "auto") ?: "auto"; set(v) { p.edit().putString("language", v).apply() }
    var model: String get() = p.getString("model", "whisper-large-v3-turbo") ?: "whisper-large-v3-turbo"; set(v) { p.edit().putString("model", v).apply() }
    var grammar: Boolean get() = p.getBoolean("grammar", true); set(v) { p.edit().putBoolean("grammar", v).apply() }
    var autoStart: Boolean get() = p.getBoolean("auto_start", false); set(v) { p.edit().putBoolean("auto_start", v).apply() }
    var floatingPillX: Int get() = p.getInt("floating_pill_x", Int.MIN_VALUE); set(v) { p.edit().putInt("floating_pill_x", v).apply() }
    var floatingPillY: Int get() = p.getInt("floating_pill_y", Int.MIN_VALUE); set(v) { p.edit().putInt("floating_pill_y", v).apply() }

    /**
     * History retention in days. 0 = show all ("Forever").
     * Backed by a [MutableStateFlow] so [MainViewModel] reacts immediately
     * when the user changes the setting, without an app restart.
     */
    private val _retentionFlow = MutableStateFlow(p.getInt("retention", 30))
    val retentionFlow: StateFlow<Int> = _retentionFlow.asStateFlow()

    var retention: Int
        get() = _retentionFlow.value
        set(v) {
            p.edit().putInt("retention", v).apply()
            _retentionFlow.value = v
        }

    /**
     * Selected theme — "system" | "light" | "dark".
     * Backed by a [MutableStateFlow] so any collector (e.g. MainActivity) reacts
     * immediately when the user changes the setting in Settings, with no app restart.
     */
    private val _themeFlow = MutableStateFlow(p.getString("theme", "system") ?: "system")
    val themeFlow: StateFlow<String> = _themeFlow.asStateFlow()

    var theme: String
        get() = _themeFlow.value
        set(v) {
            p.edit().putString("theme", v).apply()
            _themeFlow.value = v
        }

    /**
     * AI Grammar Correction toggle — Default: OFF (false).
     */
    var grammarCorrectionEnabled: Boolean
        get() = p.getBoolean("ai_grammar_correction_enabled", false)
        set(v) { p.edit().putBoolean("ai_grammar_correction_enabled", v).apply() }

    /**
     * Auto Enhance After Transcription — Default: OFF (false).
     */
    var autoEnhanceAfterTranscription: Boolean
        get() = p.getBoolean("ai_auto_enhance_enabled", false)
        set(v) { p.edit().putBoolean("ai_auto_enhance_enabled", v).apply() }

    /**
     * Default Rewrite Style — Default: "professional".
     */
    var defaultRewriteStyle: String
        get() = p.getString("ai_default_rewrite_style", "professional") ?: "professional"
        set(v) { p.edit().putString("ai_default_rewrite_style", v).apply() }

    /**
     * Default AI Provider — Default: "groq".
     */
    var defaultAiProvider: String
        get() = p.getString("ai_default_provider", "groq") ?: "groq"
        set(v) { p.edit().putString("ai_default_provider", v).apply() }

    /**
     * Onboarding completed flag — Default: false.
     */
    var onboardingCompleted: Boolean
        get() = p.getBoolean("onboarding_completed", false)
        set(v) { p.edit().putBoolean("onboarding_completed", v).apply() }

    /**
     * Floating mic pill enabled — Default: true.
     *
     * When false, [PillOverlayService] is stopped immediately and will not
     * be restarted until the user re-enables it.
     *
     * Backed by a [MutableStateFlow] so [PillOverlayService] and the main
     * screen react without an app restart.
     */
    private val _floatingPillEnabledFlow = MutableStateFlow(p.getBoolean("floating_pill_enabled", false))
    val floatingPillEnabledFlow: StateFlow<Boolean> = _floatingPillEnabledFlow.asStateFlow()

    var floatingPillEnabled: Boolean
        get() = _floatingPillEnabledFlow.value
        set(v) {
            p.edit().putBoolean("floating_pill_enabled", v).apply()
            _floatingPillEnabledFlow.value = v
        }

    /**
     * Global output language for all AI rewrite operations (presets, custom prompts,
     * translations). Default: "English".
     *
     * This is the single source of truth — every rewrite request reads this value.
     * Persisted across app restarts. Never reset by provider switches.
     */
    var outputLanguage: String
        get() = p.getString("ai_output_language", "English") ?: "English"
        set(v) { p.edit().putString("ai_output_language", v).apply() }
}

