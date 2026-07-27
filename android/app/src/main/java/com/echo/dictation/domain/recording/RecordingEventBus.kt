package com.echo.dictation.domain.recording

import com.echo.dictation.domain.model.Transcription
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Application-scoped event bus that bridges [PillController] (service layer)
 * with [MainViewModel] (presentation layer) without creating a direct dependency
 * between a Service singleton and a ViewModel.
 *
 * Every successfully persisted transcription — regardless of whether it was
 * pasted into a text field or fell back to the clipboard — is emitted here so
 * the History screen and clipboard auto-copy logic always fire.
 */
@Singleton
class RecordingEventBus @Inject constructor() {

    private val _completedTranscriptions = MutableSharedFlow<Transcription>(
        replay     = 1,         // new collectors see the most recent result immediately
        extraBufferCapacity = 10,
    )

    /** Emits every transcription that was successfully saved to Room. */
    val completedTranscriptions: SharedFlow<Transcription> =
        _completedTranscriptions.asSharedFlow()

    suspend fun emitCompleted(transcription: Transcription) {
        _completedTranscriptions.emit(transcription)
    }
}
