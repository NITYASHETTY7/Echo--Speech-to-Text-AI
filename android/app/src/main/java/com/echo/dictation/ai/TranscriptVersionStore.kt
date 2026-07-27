package com.echo.dictation.ai

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import javax.inject.Inject
import javax.inject.Singleton

/**
 * In-memory store for the current transcription session's [TranscriptVersion] history.
 *
 * Persisted only for the lifetime of the current session (app process). Room
 * persistence can be added later by replacing this class without changing any
 * ViewModel or UI code.
 *
 * Rules:
 *  - The original raw version is always stored first and never removed.
 *  - New versions are appended; the original is never replaced.
 *  - The active version index is tracked separately so the user can freely switch.
 */
@Singleton
class TranscriptVersionStore @Inject constructor() {

    private val _versions = MutableStateFlow<List<TranscriptVersion>>(emptyList())
    val versions: StateFlow<List<TranscriptVersion>> = _versions.asStateFlow()

    private val _activeIndex = MutableStateFlow(0)
    val activeIndex: StateFlow<Int> = _activeIndex.asStateFlow()

    /** Returns the currently displayed version, or null when no session is active. */
    val activeVersion: TranscriptVersion?
        get() = _versions.value.getOrNull(_activeIndex.value)

    /**
     * Start a new transcription session.
     * All previous versions are discarded and replaced by [rawText].
     */
    fun startNewSession(rawText: String) {
        val original = TranscriptVersion(
            id    = "v_${System.currentTimeMillis()}_0",
            text  = rawText,
            kind  = VersionKind.Original,
            label = "Original",
        )
        _versions.value = listOf(original)
        _activeIndex.value = 0
    }

    /**
     * Append a new AI-produced version and make it the active version.
     */
    fun addVersion(version: TranscriptVersion) {
        _versions.update { it + version }
        _activeIndex.value = _versions.value.lastIndex
    }

    /**
     * Switch the active version to [index] without modifying the list.
     * Does nothing if [index] is out of range.
     */
    fun setActiveIndex(index: Int) {
        if (index in _versions.value.indices) {
            _activeIndex.value = index
        }
    }

    /** True when there is at least one version in the current session. */
    val hasSession: Boolean
        get() = _versions.value.isNotEmpty()

    /** Clear all versions (e.g. when the user starts a fresh recording). */
    fun clear() {
        _versions.value = emptyList()
        _activeIndex.value = 0
    }
}
