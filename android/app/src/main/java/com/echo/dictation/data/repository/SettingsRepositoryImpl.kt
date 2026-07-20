package com.echo.dictation.data.repository

import com.echo.dictation.data.local.AppPreferences
import com.echo.dictation.domain.model.AppSettings
import com.echo.dictation.domain.repository.SettingsRepository
import com.echo.dictation.speech.provider.ProviderKeyStore
import com.echo.dictation.speech.provider.ProviderRegistry
import com.echo.dictation.speech.provider.ProviderSettings
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SettingsRepositoryImpl @Inject constructor(
    private val prefs: AppPreferences,
    private val keyStore: ProviderKeyStore,
    private val providerSettings: ProviderSettings,
) : SettingsRepository {

    private val _settings = MutableStateFlow(buildSettings())
    override val settings: StateFlow<AppSettings> = _settings.asStateFlow()

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

    private fun refresh() { _settings.value = buildSettings() }

    private fun buildSettings(): AppSettings {
        val providerConfigured = ProviderRegistry.allConfigs.associate { config ->
            config.id.name.lowercase() to keyStore.isConfigured(config.id)
        }
        return AppSettings(
            language         = prefs.language,
            model            = providerSettings.selectedModel,
            retentionDays    = prefs.retention,
            grammarEnabled   = prefs.grammar,
            theme            = prefs.theme,
            autoStart        = prefs.autoStart,
            providerConfigured = providerConfigured,
        )
    }
}
