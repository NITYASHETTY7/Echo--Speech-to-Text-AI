package com.echo.dictation.presentation.ui

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.echo.dictation.data.local.AppPreferences
import com.echo.dictation.speech.provider.GeminiModelResolver
import com.echo.dictation.speech.provider.ProviderId
import com.echo.dictation.speech.provider.ProviderConfig
import com.echo.dictation.speech.provider.ProviderKeyStore
import com.echo.dictation.speech.provider.ProviderRegistry
import com.echo.dictation.speech.provider.ProviderSettings
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
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

// ── Model-loading state ───────────────────────────────────────────────────────

sealed interface ModelLoadState {
    /** No load in progress; models list comes from ProviderRegistry (static). */
    data object Idle : ModelLoadState
    /** A network fetch is in progress (Gemini only). */
    data object Loading : ModelLoadState
    /** Fetch completed successfully; models are available in [SettingsUiState.availableModels]. */
    data object Loaded : ModelLoadState
    /** Fetch failed; user sees the error and a free-text fallback field. */
    data class Error(val message: String) : ModelLoadState
}

// ── UI state ──────────────────────────────────────────────────────────────────

data class SettingsUiState(
    // ── Speech AI ────────────────────────────────────────────────────────────
    val selectedProvider: ProviderId       = ProviderId.GROQ,
    val providerConfig: ProviderConfig     = ProviderRegistry.getConfig(ProviderId.GROQ),
    /**
     * Current API key field value.
     * Pre-populated with the stored key when one exists so the user can see /
     * edit what is saved.
     */
    val apiKeyInput: String                = "",
    /** True if the provider already has a key stored in [ProviderKeyStore]. */
    val hasStoredKey: Boolean              = false,
    val keyVisible: Boolean                = false,
    val selectedModel: String              = "whisper-large-v3-turbo",
    /**
     * Model list to display in the dropdown.
     * For providers with a static list this is set from [ProviderConfig.models].
     * For Gemini this is populated after a successful [ModelLoadState.Loaded].
     */
    val availableModels: List<String>      = emptyList(),
    /** State of the dynamic model-loading process (relevant for Gemini). */
    val modelLoadState: ModelLoadState     = ModelLoadState.Idle,
    val customBaseUrl: String              = "",
    /** Effective URL shown in the Base URL row. */
    val effectiveBaseUrl: String           = "https://api.groq.com/openai/v1/",
    // ── Connection test ───────────────────────────────────────────────────────
    val testState: TestState               = TestState.Idle,
    // ── Floating pill ─────────────────────────────────────────────────────────
    val floatingPillEnabled: Boolean       = true,
    // ── General ──────────────────────────────────────────────────────────────
    val language: String                   = "auto",
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

// ── ViewModel ─────────────────────────────────────────────────────────────────

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val keyStore: ProviderKeyStore,
    private val providerSettings: ProviderSettings,
    private val appPreferences: AppPreferences,
    private val httpClient: OkHttpClient,
    private val geminiModelResolver: GeminiModelResolver,
    @ApplicationContext private val context: Context,
) : ViewModel() {

    private val _state = MutableStateFlow(buildInitialState())
    val state: StateFlow<SettingsUiState> = _state.asStateFlow()

    /** Debounce job for auto-saving the API key as the user types. */
    private var autoSaveJob: Job? = null

    init {
        // If the current provider is Gemini and has a stored key, load models on startup.
        val initial = _state.value
        if (initial.selectedProvider == ProviderId.GEMINI && initial.hasStoredKey) {
            loadModelsForProvider(ProviderId.GEMINI, keyStore.getKey(ProviderId.GEMINI) ?: "")
        }
    }

    private fun buildInitialState(): SettingsUiState {
        val provider   = providerSettings.selectedProvider
        val config     = ProviderRegistry.getConfig(provider)
        val model      = providerSettings.getModelForProvider(provider)
        val customUrl  = providerSettings.getBaseUrlForProvider(provider)
        val storedKey  = keyStore.getKey(provider) ?: ""
        return SettingsUiState(
            selectedProvider    = provider,
            providerConfig      = config,
            // Field always starts blank — stored key is indicated by hasStoredKey.
            // User types a new key to update; field clears again after auto-save.
            apiKeyInput         = "",
            hasStoredKey        = storedKey.isNotBlank(),
            keyVisible          = false,
            selectedModel       = model,
            availableModels     = config.models,
            modelLoadState      = ModelLoadState.Idle,
            customBaseUrl       = customUrl,
            effectiveBaseUrl    = if (config.requiresCustomBaseUrl) customUrl else config.defaultBaseUrl,
            floatingPillEnabled = appPreferences.floatingPillEnabled,
            language            = appPreferences.language,
            retentionDays       = appPreferences.retention,
            theme               = appPreferences.theme,
        )
    }

    // ── Provider selection ────────────────────────────────────────────────────

    fun onProviderSelected(id: ProviderId) {
        val config       = ProviderRegistry.getConfig(id)
        val storedModel  = providerSettings.getModelForProvider(id)
        val storedUrl    = providerSettings.getBaseUrlForProvider(id)
        val effectiveUrl = if (config.requiresCustomBaseUrl) storedUrl else config.defaultBaseUrl
        val storedKey    = keyStore.getKey(id) ?: ""

        providerSettings.selectedProvider = id
        autoSaveJob?.cancel()

        _state.value = _state.value.copy(
            selectedProvider  = id,
            providerConfig    = config,
            // Field is blank on switch; hasStoredKey reflects whether a key exists.
            apiKeyInput       = "",
            hasStoredKey      = storedKey.isNotBlank(),
            keyVisible        = false,
            selectedModel     = storedModel,
            availableModels   = config.models,
            modelLoadState    = ModelLoadState.Idle,
            customBaseUrl     = storedUrl,
            effectiveBaseUrl  = effectiveUrl,
            testState         = TestState.Idle,
        )

        // If Gemini is selected and already has a key, fetch its model list immediately.
        if (id == ProviderId.GEMINI && storedKey.isNotBlank()) {
            loadModelsForProvider(id, storedKey)
        }
    }

    // ── API key ───────────────────────────────────────────────────────────────

    /**
     * Called on every keystroke. Updates the field value immediately and schedules
     * an auto-save after [AUTO_SAVE_DELAY_MS] of inactivity. When the save fires:
     *   1. Key is persisted to [ProviderKeyStore].
     *   2. Field is cleared back to blank — indicating "key stored, field is empty".
     *   3. [hasStoredKey] is set to true so the "API key saved" indicator appears.
     *   4. Model loading is triggered for the provider.
     */
    fun onApiKeyChanged(value: String) {
        _state.value = _state.value.copy(apiKeyInput = value, testState = TestState.Idle)

        autoSaveJob?.cancel()
        if (value.isBlank()) return

        autoSaveJob = viewModelScope.launch {
            delay(AUTO_SAVE_DELAY_MS)
            val key = _state.value.apiKeyInput.trim()
            if (key.isBlank()) return@launch

            val provider = _state.value.selectedProvider
            keyStore.setKey(provider, key)

            if (provider == ProviderId.GEMINI) {
                geminiModelResolver.invalidateCacheForKey(key)
            }

            // Clear the field — saved state is communicated via hasStoredKey only.
            _state.value = _state.value.copy(
                apiKeyInput  = "",
                hasStoredKey = true,
                keyVisible   = false,
                testState    = TestState.Idle,
            )

            loadModelsForProvider(provider, key)
        }
    }

    fun onToggleKeyVisibility() {
        _state.value = _state.value.copy(keyVisible = !_state.value.keyVisible)
    }

    fun onClearKey() {
        autoSaveJob?.cancel()
        keyStore.clearKey(_state.value.selectedProvider)
        _state.value = _state.value.copy(
            apiKeyInput     = "",
            hasStoredKey    = false,
            keyVisible      = false,
            availableModels = _state.value.providerConfig.models,
            modelLoadState  = ModelLoadState.Idle,
            testState       = TestState.Idle,
        )
    }

    // ── Model loading ─────────────────────────────────────────────────────────

    /**
     * Loads the model list for [provider].
     *
     * - Static-list providers (Groq, OpenAI, etc.): sets [availableModels] from
     *   [ProviderConfig.models] and auto-selects the first entry if nothing is
     *   saved yet.
     *
     * - Gemini: launches a background coroutine that calls [GeminiModelResolver]
     *   over the network. Updates [modelLoadState] through Loading → Loaded/Error.
     *   On success, auto-selects the top-ranked model and persists it.
     */
    private fun loadModelsForProvider(provider: ProviderId, apiKey: String) {
        val config = ProviderRegistry.getConfig(provider)

        when {
            // ── Gemini: dynamic fetch ───────────────────────────────────────
            provider == ProviderId.GEMINI -> {
                _state.value = _state.value.copy(modelLoadState = ModelLoadState.Loading)

                viewModelScope.launch(Dispatchers.IO) {
                    val result = runCatching {
                        geminiModelResolver.resolveModel(apiKey)
                    }

                    withContext(Dispatchers.Main) {
                        result.fold(
                            onSuccess = { bestModel ->
                                // Use the session-ranked list for the dropdown.
                                // getCachedRankedModels returns what was fetched during resolveModel.
                                val rankedList = geminiModelResolver.getCachedRankedModels(apiKey)
                                val allModels = if (rankedList.isNotEmpty()) rankedList
                                               else listOf(bestModel)

                                // Persist the auto-selected model.
                                providerSettings.setModelForProvider(provider, bestModel)

                                _state.value = _state.value.copy(
                                    availableModels = allModels,
                                    selectedModel   = bestModel,
                                    modelLoadState  = ModelLoadState.Loaded,
                                )
                            },
                            onFailure = { error ->
                                val msg = when (error) {
                                    is java.net.UnknownHostException ->
                                        "No internet — cannot fetch Gemini models"
                                    is java.net.SocketTimeoutException ->
                                        "Request timed out fetching models"
                                    else -> error.message ?: "Could not load models"
                                }
                                _state.value = _state.value.copy(
                                    modelLoadState = ModelLoadState.Error(msg),
                                )
                            }
                        )
                    }
                }
            }

            // ── Providers with static model lists ───────────────────────────
            config.models.isNotEmpty() -> {
                val currentModel = _state.value.selectedModel
                val autoSelected = if (currentModel.isBlank() || currentModel !in config.models) {
                    config.models.first().also { first ->
                        providerSettings.setModelForProvider(provider, first)
                    }
                } else {
                    currentModel
                }
                _state.value = _state.value.copy(
                    availableModels = config.models,
                    selectedModel   = autoSelected,
                    modelLoadState  = ModelLoadState.Idle,
                )
            }

            // ── Azure / Custom: user enters model name manually ─────────────
            else -> {
                _state.value = _state.value.copy(
                    availableModels = emptyList(),
                    modelLoadState  = ModelLoadState.Idle,
                )
            }
        }
    }

    // ── Model selection ───────────────────────────────────────────────────────

    fun onModelSelected(model: String) {
        providerSettings.setModelForProvider(_state.value.selectedProvider, model)
        _state.value = _state.value.copy(selectedModel = model, testState = TestState.Idle)
    }

    // ── Base URL ──────────────────────────────────────────────────────────────

    fun onBaseUrlChanged(url: String) {
        providerSettings.setBaseUrlForProvider(_state.value.selectedProvider, url)
        _state.value = _state.value.copy(
            customBaseUrl    = url,
            effectiveBaseUrl = url,
            testState        = TestState.Idle,
        )
    }

    // ── Connection test ───────────────────────────────────────────────────────

    fun onTestConnection() {
        val current    = _state.value
        val providerId = current.selectedProvider
        val apiKey = keyStore.getKey(providerId)?.takeIf { it.isNotBlank() }
            ?: current.apiKeyInput.trim().takeIf { it.isNotBlank() }
            ?: run {
                _state.value = current.copy(testState = TestState.Error("No API key entered"))
                return
            }

        val config  = current.providerConfig
        val baseUrl = if (config.requiresCustomBaseUrl) current.customBaseUrl
                      else config.defaultBaseUrl
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
            val start    = System.currentTimeMillis()
            val response = httpClient.newCall(requestBuilder.build()).execute()
            val latency  = System.currentTimeMillis() - start
            response.body?.close()
            when {
                response.isSuccessful                                           -> TestState.Success(latency)
                providerId == ProviderId.AZURE && response.code == 404         -> TestState.Success(latency)
                response.code == 401 -> TestState.Error("HTTP 401 — Invalid API key")
                response.code == 403 -> TestState.Error("HTTP 403 — Forbidden (check key permissions)")
                response.code == 429 -> TestState.Error("HTTP 429 — Rate limit exceeded")
                response.code == 404 -> TestState.Error("HTTP 404 — Endpoint not found (check Base URL)")
                else                 -> TestState.Error("HTTP ${response.code}")
            }
        } catch (e: UnknownHostException)    { TestState.Error("Network unavailable — cannot reach ${config.displayName}") }
        catch  (e: SocketTimeoutException)   { TestState.Error("Request timed out") }
        catch  (e: javax.net.ssl.SSLException) { TestState.Error("SSL error: ${e.message}") }
        catch  (e: Exception)               { TestState.Error(e.message ?: "Unknown error") }
    }

    // ── Floating pill ─────────────────────────────────────────────────────────

    fun onFloatingPillToggled(enabled: Boolean) {
        appPreferences.floatingPillEnabled = enabled
        _state.value = _state.value.copy(floatingPillEnabled = enabled)
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

    companion object {
        /** Milliseconds of inactivity after a keystroke before the key is auto-saved. */
        private const val AUTO_SAVE_DELAY_MS = 600L
    }
}
