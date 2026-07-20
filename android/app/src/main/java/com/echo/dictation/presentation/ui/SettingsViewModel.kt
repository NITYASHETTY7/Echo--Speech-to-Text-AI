package com.echo.dictation.presentation.ui

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.echo.dictation.data.local.AppPreferences
import com.echo.dictation.speech.provider.ProviderConfig
import com.echo.dictation.speech.provider.ProviderId
import com.echo.dictation.speech.provider.ProviderKeyStore
import com.echo.dictation.speech.provider.ProviderRegistry
import com.echo.dictation.speech.provider.ProviderSettings
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import javax.inject.Inject

data class SettingsUiState(
    // ── Speech AI ────────────────────────────────────────────────────────────
    val selectedProvider: ProviderId       = ProviderId.GROQ,
    val providerConfig: ProviderConfig     = ProviderRegistry.getConfig(ProviderId.GROQ),
    /** Current API key field value — empty while provider has a saved key (shown as dots). */
    val apiKeyInput: String                = "",
    /** True if the provider already has a key stored (field shows placeholder dots). */
    val hasStoredKey: Boolean              = false,
    val keyVisible: Boolean                = false,
    val selectedModel: String              = "whisper-large-v3-turbo",
    val customBaseUrl: String              = "",
    /** Effective URL shown in the Base URL row. */
    val effectiveBaseUrl: String           = "https://api.groq.com/openai/v1/",
    // ── Connection test ───────────────────────────────────────────────────────
    val testState: TestState               = TestState.Idle,
    // ── General ──────────────────────────────────────────────────────────────
    val language: String                   = "en",
    val retentionDays: Int                 = 30,
    val theme: String                      = "system",
    val saving: Boolean                    = false,
)

sealed interface TestState {
    data object Idle : TestState
    data object Testing : TestState
    data class Success(val latencyMs: Long) : TestState
    data class Error(val message: String) : TestState
}

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val keyStore: ProviderKeyStore,
    private val providerSettings: ProviderSettings,
    private val appPreferences: AppPreferences,
    private val httpClient: OkHttpClient,
    @ApplicationContext private val context: Context,
) : ViewModel() {

    private val _state = MutableStateFlow(buildInitialState())
    val state: StateFlow<SettingsUiState> = _state.asStateFlow()

    private fun buildInitialState(): SettingsUiState {
        val provider = providerSettings.selectedProvider
        val config   = ProviderRegistry.getConfig(provider)
        val model    = providerSettings.selectedModel
        val customUrl = providerSettings.customBaseUrl
        return SettingsUiState(
            selectedProvider = provider,
            providerConfig   = config,
            apiKeyInput      = "",
            hasStoredKey     = keyStore.isConfigured(provider),
            keyVisible       = false,
            selectedModel    = model,
            customBaseUrl    = customUrl,
            effectiveBaseUrl = if (config.requiresCustomBaseUrl) customUrl else config.defaultBaseUrl,
            language         = appPreferences.language,
            retentionDays    = appPreferences.retention,
            theme            = appPreferences.theme,
        )
    }

    // ── Provider selection ────────────────────────────────────────────────────

    fun onProviderSelected(id: ProviderId) {
        val config = ProviderRegistry.getConfig(id)
        val defaultModel = config.models.firstOrNull() ?: ""
        val storedCustomUrl = providerSettings.customBaseUrl
        val effectiveUrl = if (config.requiresCustomBaseUrl) storedCustomUrl else config.defaultBaseUrl

        providerSettings.selectedProvider = id
        // Reset model to this provider's default
        providerSettings.selectedModel = defaultModel

        _state.value = _state.value.copy(
            selectedProvider = id,
            providerConfig   = config,
            apiKeyInput      = "",
            hasStoredKey     = keyStore.isConfigured(id),
            keyVisible       = false,
            selectedModel    = defaultModel,
            customBaseUrl    = storedCustomUrl,
            effectiveBaseUrl = effectiveUrl,
            testState        = TestState.Idle,
        )
    }

    // ── API key ───────────────────────────────────────────────────────────────

    fun onApiKeyChanged(value: String) {
        _state.value = _state.value.copy(apiKeyInput = value, testState = TestState.Idle)
    }

    fun onToggleKeyVisibility() {
        _state.value = _state.value.copy(keyVisible = !_state.value.keyVisible)
    }

    fun onClearKey() {
        keyStore.clearKey(_state.value.selectedProvider)
        _state.value = _state.value.copy(
            apiKeyInput  = "",
            hasStoredKey = false,
            keyVisible   = false,
            testState    = TestState.Idle,
        )
    }

    fun onSaveKey() {
        val key = _state.value.apiKeyInput.trim()
        if (key.isBlank()) return
        keyStore.setKey(_state.value.selectedProvider, key)
        _state.value = _state.value.copy(
            apiKeyInput  = "",
            hasStoredKey = true,
            keyVisible   = false,
            testState    = TestState.Idle,
        )
    }

    // ── Model ─────────────────────────────────────────────────────────────────

    fun onModelSelected(model: String) {
        providerSettings.selectedModel = model
        _state.value = _state.value.copy(selectedModel = model, testState = TestState.Idle)
    }

    // ── Base URL ──────────────────────────────────────────────────────────────

    fun onBaseUrlChanged(url: String) {
        providerSettings.customBaseUrl = url
        _state.value = _state.value.copy(
            customBaseUrl    = url,
            effectiveBaseUrl = url,
            testState        = TestState.Idle,
        )
    }

    // ── Connection test ───────────────────────────────────────────────────────

    fun onTestConnection() {
        val current = _state.value
        val providerId = current.selectedProvider
        val apiKey = keyStore.getKey(providerId)?.takeIf { it.isNotBlank() }
            ?: current.apiKeyInput.trim().takeIf { it.isNotBlank() }
            ?: run {
                _state.value = current.copy(testState = TestState.Error("No API key entered"))
                return
            }

        val config = current.providerConfig
        val baseUrl = if (config.requiresCustomBaseUrl) current.customBaseUrl else config.defaultBaseUrl
        if (config.requiresCustomBaseUrl && baseUrl.isBlank()) {
            _state.value = current.copy(testState = TestState.Error("Base URL is required"))
            return
        }

        _state.value = current.copy(testState = TestState.Testing)

        viewModelScope.launch(Dispatchers.IO) {
            val result = runTestRequest(providerId, apiKey, baseUrl, config)
            withContext(Dispatchers.Main) {
                _state.value = _state.value.copy(testState = result)
            }
        }
    }

    private fun runTestRequest(
        providerId: ProviderId,
        apiKey: String,
        baseUrl: String,
        config: ProviderConfig,
    ): TestState {
        val testUrl = when (providerId) {
            ProviderId.DEEPGRAM   -> "https://api.deepgram.com/v1/projects"
            ProviderId.ASSEMBLYAI -> "https://api.assemblyai.com/v2/account"
            ProviderId.GEMINI     -> "https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey"
            else                  -> "${baseUrl.trimEnd('/')}/models"
        }

        val requestBuilder = Request.Builder().url(testUrl).get()

        when (providerId) {
            ProviderId.GEMINI -> { /* key in URL */ }
            else -> requestBuilder.header(config.authHeaderName, config.authValueFormat.format(apiKey))
        }

        return try {
            val start = System.currentTimeMillis()
            val response = httpClient.newCall(requestBuilder.build()).execute()
            val latency = System.currentTimeMillis() - start
            response.body?.close()
            when {
                response.isSuccessful -> TestState.Success(latency)
                // 404 on /models is still valid auth (Azure sometimes returns 404 here)
                providerId == ProviderId.AZURE && response.code == 404 -> TestState.Success(latency)
                response.code == 401 -> TestState.Error("HTTP 401 — Invalid API key")
                response.code == 403 -> TestState.Error("HTTP 403 — Forbidden (check key permissions)")
                response.code == 429 -> TestState.Error("HTTP 429 — Rate limit exceeded")
                response.code == 404 -> TestState.Error("HTTP 404 — Endpoint not found (check Base URL)")
                else                 -> TestState.Error("HTTP ${response.code}")
            }
        } catch (e: UnknownHostException) {
            TestState.Error("Network unavailable — cannot reach ${config.displayName}")
        } catch (e: SocketTimeoutException) {
            TestState.Error("Request timed out")
        } catch (e: javax.net.ssl.SSLException) {
            TestState.Error("SSL error: ${e.message}")
        } catch (e: Exception) {
            TestState.Error(e.message ?: "Unknown error")
        }
    }

    // ── General settings ──────────────────────────────────────────────────────

    fun onLanguageChanged(lang: String) {
        appPreferences.language = lang
        _state.value = _state.value.copy(language = lang)
    }

    fun onRetentionChanged(days: Int) {
        appPreferences.retention = days
        _state.value = _state.value.copy(retentionDays = days)
    }

    fun onThemeChanged(t: String) {
        appPreferences.theme = t
        _state.value = _state.value.copy(theme = t)
    }
}
