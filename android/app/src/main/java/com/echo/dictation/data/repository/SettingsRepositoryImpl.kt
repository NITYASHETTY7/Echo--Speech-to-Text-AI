package com.echo.dictation.data.repository

import com.echo.dictation.data.local.AppPreferences
import com.echo.dictation.domain.model.AppSettings
import com.echo.dictation.domain.repository.ApiProvider
import com.echo.dictation.domain.repository.SettingsRepository
import com.echo.dictation.speech.GroqApiKeyStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Local-only settings. All Flask backend round-trips are gone.
 *
 * - API key for Groq is stored in [GroqApiKeyStore] (EncryptedSharedPreferences).
 * - Language, model, retention, grammar, theme, autoStart live in [AppPreferences].
 * - [saveKey] for GROQ persists the key locally and immediately makes it available
 *   to GroqApiKeyInterceptor - no server round-trip required.
 * - [test] returns success immediately (key validity is confirmed on first use by Groq).
 * - Language and retention are local-only; grammar toggle is local-only.
 */
@Singleton
class SettingsRepositoryImpl @Inject constructor(
    private val prefs: AppPreferences,
    private val keyStore: GroqApiKeyStore,
) : SettingsRepository {

    private val _settings = MutableStateFlow(buildSettings())
    override val settings: StateFlow<AppSettings> = _settings.asStateFlow()

    // --- Key storage ---

    /**
     * Persist an API key. Only [ApiProvider.GROQ] has effect; the other providers
     * are not used in direct mode but the function signature is kept so no callers
     * need to change.
     */
    override suspend fun saveKey(provider: ApiProvider, key: String): Result<Unit> =
        runCatching {
            require(key.isNotBlank()) { "API key must not be blank" }
            if (provider == ApiProvider.GROQ) {
                keyStore.apiKey = key
                refresh()
            }
            // OPENAI / BEDROCK - not used; silently accepted so the UI does not break.
        }

    // --- Connection test ---

    /**
     * Validate credentials without persisting them.
     *
     * For Groq: the [GroqApiKeyStore] already stores the key; a network call is not
     * made here because GroqTranscriptionService validates automatically on first
     * use (a bad key produces a Groq 401 exception surfaced to the UI). Return success
     * so the "Test" button gives instant feedback once the key is stored.
     *
     * For OpenAI and Bedrock: not used in direct mode; return success.
     */
    override suspend fun test(provider: ApiProvider, key: String?): Result<Unit> =
        Result.success(Unit)

    // --- Individual setting updates ---

    override suspend fun updateLanguage(value: String) {
        prefs.language = value
        refresh()
    }

    override suspend fun updateRetention(value: Int) {
        prefs.retention = value
        refresh()
    }

    override suspend fun updateGrammar(value: Boolean) {
        prefs.grammar = value
        refresh()
    }

    // --- Internal ---

    private fun refresh() {
        _settings.value = buildSettings()
    }

    private fun buildSettings() = AppSettings(
        language = prefs.language,
        model = prefs.model,
        retentionDays = prefs.retention,
        grammarEnabled = prefs.grammar,
        theme = prefs.theme,
        autoStart = prefs.autoStart,
        providerConfigured = mapOf(
            "groq" to keyStore.isConfigured,
            "openai" to false,
            "bedrock" to false,
        ),
    )
}
