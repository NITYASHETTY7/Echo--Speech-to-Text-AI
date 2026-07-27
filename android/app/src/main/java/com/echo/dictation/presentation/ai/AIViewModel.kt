package com.echo.dictation.presentation.ai

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.echo.dictation.data.local.AppPreferences
import com.echo.dictation.domain.ai.AIJob
import com.echo.dictation.domain.ai.AIService
import com.echo.dictation.domain.ai.PromptTemplate
import com.echo.dictation.domain.ai.TranscriptVersion
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

data class AiUiState(
    val transcriptId: String = "",
    val versions: List<TranscriptVersion> = emptyList(),
    val latestJob: AIJob? = null,
    val activeIndex: Int = 0,
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
    val successMessage: String? = null,
    val grammarCorrectionEnabled: Boolean = false,
    val autoEnhanceEnabled: Boolean = false,
    val defaultStyle: String = "professional",
    val defaultProvider: String = "groq",
    val isRewriteSheetVisible: Boolean = false,
    val customPromptText: String = "",
) {
    val activeVersion: TranscriptVersion? get() = versions.getOrNull(activeIndex)
    val hasVersions: Boolean get() = versions.isNotEmpty()
    val isCustomPromptValid: Boolean get() = customPromptText.trim().isNotBlank() && customPromptText.length <= 500
}

@OptIn(ExperimentalCoroutinesApi::class)
@HiltViewModel
class AIViewModel @Inject constructor(
    private val aiService: AIService,
    private val prefs: AppPreferences,
) : ViewModel() {

    private val _currentTranscriptId = MutableStateFlow("")
    private val _isLoading = MutableStateFlow(false)
    private val _errorMessage = MutableStateFlow<String?>(null)
    private val _successMessage = MutableStateFlow<String?>(null)
    private val _grammarEnabled = MutableStateFlow(prefs.grammarCorrectionEnabled)
    private val _autoEnhanceEnabled = MutableStateFlow(prefs.autoEnhanceAfterTranscription)
    private val _defaultStyle = MutableStateFlow(prefs.defaultRewriteStyle)
    private val _defaultProvider = MutableStateFlow(prefs.defaultAiProvider)
    private val _isRewriteSheetVisible = MutableStateFlow(false)
    private val _customPromptText = MutableStateFlow("")
    private val _activeIndex = MutableStateFlow(0)

    private val _versionsFlow = _currentTranscriptId.flatMapLatest { id ->
        if (id.isBlank()) flowOf(emptyList()) else aiService.getTranscriptVersions(id)
    }

    private val _latestJobFlow = _currentTranscriptId.flatMapLatest { id ->
        if (id.isBlank()) flowOf(null) else aiService.getLatestJobForTranscript(id)
    }

    val state: StateFlow<AiUiState> = combine(
        _currentTranscriptId,
        _versionsFlow,
        _latestJobFlow,
        _isLoading,
        _errorMessage,
        _successMessage,
        _grammarEnabled,
        _autoEnhanceEnabled,
        _defaultStyle,
        _defaultProvider,
        _isRewriteSheetVisible,
        _customPromptText,
        _activeIndex,
    ) { args ->
        val transcriptId = args[0] as String
        @Suppress("UNCHECKED_CAST")
        val versions = args[1] as List<TranscriptVersion>
        val latestJob = args[2] as AIJob?
        val isLoading = args[3] as Boolean
        val errorMessage = args[4] as String?
        val successMessage = args[5] as String?
        val grammarEnabled = args[6] as Boolean
        val autoEnhance = args[7] as Boolean
        val defaultStyle = args[8] as String
        val defaultProvider = args[9] as String
        val isSheetVisible = args[10] as Boolean
        val customPrompt = args[11] as String
        val activeIndex = args[12] as Int

        AiUiState(
            transcriptId = transcriptId,
            versions = versions,
            latestJob = latestJob,
            activeIndex = if (activeIndex in versions.indices) activeIndex else (versions.lastIndex.coerceAtLeast(0)),
            isLoading = isLoading,
            errorMessage = errorMessage,
            successMessage = successMessage,
            grammarCorrectionEnabled = grammarEnabled,
            autoEnhanceEnabled = autoEnhance,
            defaultStyle = defaultStyle,
            defaultProvider = defaultProvider,
            isRewriteSheetVisible = isSheetVisible,
            customPromptText = customPrompt
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5000),
        initialValue = AiUiState()
    )

    fun loadTranscript(transcriptId: String) {
        _currentTranscriptId.value = transcriptId
        // Reset to 0; the combine() block will clamp it to lastIndex if needed
        // so the latest version is shown by default (see activeIndex logic below).
        _activeIndex.value = Int.MAX_VALUE  // will be clamped to lastIndex by combine
    }

    fun setGrammarCorrectionEnabled(enabled: Boolean) {
        prefs.grammarCorrectionEnabled = enabled
        _grammarEnabled.value = enabled
    }

    fun setAutoEnhanceEnabled(enabled: Boolean) {
        prefs.autoEnhanceAfterTranscription = enabled
        _autoEnhanceEnabled.value = enabled
    }

    fun setDefaultStyle(style: String) {
        prefs.defaultRewriteStyle = style
        _defaultStyle.value = style
    }

    fun setDefaultProvider(provider: String) {
        prefs.defaultAiProvider = provider
        _defaultProvider.value = provider
    }

    fun selectVersion(index: Int) {
        _activeIndex.value = index
    }

    fun showRewriteSheet() {
        _isRewriteSheetVisible.value = true
    }

    fun hideRewriteSheet() {
        _isRewriteSheetVisible.value = false
    }

    fun onCustomPromptChanged(text: String) {
        if (text.length <= 500) {
            _customPromptText.value = text
        }
    }

    fun getPromptTemplates(): List<PromptTemplate> = aiService.getPromptTemplates()

    fun applyPreset(transcriptId: String, sourceText: String, templateId: String) {
        viewModelScope.launch {
            _isLoading.value = true
            _errorMessage.value = null
            hideRewriteSheet()

            aiService.applyRewritePreset(transcriptId, sourceText, templateId)
                .onSuccess { version ->
                    _isLoading.value = false
                    _successMessage.value = "Created new version: ${version.versionType.displayName}"
                }
                .onFailure { ex ->
                    _isLoading.value = false
                    _errorMessage.value = ex.message ?: "Rewrite operation failed"
                }
        }
    }

    fun applyTranslation(transcriptId: String, sourceText: String, targetLanguage: String) {
        viewModelScope.launch {
            _isLoading.value = true
            _errorMessage.value = null
            hideRewriteSheet()
            aiService.applyTranslation(transcriptId, sourceText, targetLanguage)
                .onSuccess { version ->
                    _isLoading.value = false
                    _successMessage.value = "Translated to $targetLanguage"
                }
                .onFailure { ex ->
                    _isLoading.value = false
                    _errorMessage.value = ex.message ?: "Translation failed"
                }
        }
    }

    fun applyCustomPrompt(transcriptId: String, sourceText: String) {
        val instruction = _customPromptText.value.trim()
        if (instruction.isBlank()) {
            _errorMessage.value = "Custom prompt cannot be empty"
            return
        }

        viewModelScope.launch {
            _isLoading.value = true
            _errorMessage.value = null
            hideRewriteSheet()

            aiService.applyCustomRewrite(transcriptId, sourceText, instruction)
                .onSuccess { version ->
                    _isLoading.value = false
                    _customPromptText.value = ""
                    _successMessage.value = "Created custom rewrite version"
                }
                .onFailure { ex ->
                    _isLoading.value = false
                    _errorMessage.value = ex.message ?: "Custom rewrite failed"
                }
        }
    }

    fun retryFailedJob(transcriptId: String, sourceText: String) {
        val lastJob = state.value.latestJob ?: return
        if (lastJob.promptTemplateId != null) {
            applyPreset(transcriptId, sourceText, lastJob.promptTemplateId)
        } else {
            applyCustomPrompt(transcriptId, sourceText)
        }
    }

    fun dismissSuccess() {
        _successMessage.value = null
    }

    fun dismissError() {
        _errorMessage.value = null
    }
}
