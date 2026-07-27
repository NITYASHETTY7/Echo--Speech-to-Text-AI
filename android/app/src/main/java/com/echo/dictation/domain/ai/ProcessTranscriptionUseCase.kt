package com.echo.dictation.domain.ai

import android.util.Log
import com.echo.dictation.data.local.AppPreferences
import com.echo.dictation.domain.model.Transcription
import com.echo.dictation.domain.repository.TranscriptionRepository
import com.echo.dictation.domain.sync.SyncManager
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Orchestrates the full recording → display pipeline.
 *
 * Steps:
 *  1. STT via [TranscriptionRepository.transcribe] — saves raw transcript + VersionType.Original.
 *  2. AI post-processing via [AIService.processPostTranscription]:
 *       - Skipped if the device has no internet connection.
 *       - Grammar Correction  (if enabled) → saves VersionType.GrammarCorrected
 *       - Auto Enhance        (if enabled) → saves VersionType.AutoEnhanced
 *     Returns the final text.
 *  3. Updates `transcription.text` in Room to the final text.
 *  4. Returns the updated [Transcription].
 *
 * Note: STT itself also requires internet (Groq Whisper). If connectivity is lost
 * between recording and the STT call, [TranscriptionRepository.transcribe] will
 * return a failure — handled upstream by [PillController].
 */
@Singleton
class ProcessTranscriptionUseCase @Inject constructor(
    private val transcriptionRepository: TranscriptionRepository,
    private val aiService: AIService,
    private val prefs: AppPreferences,
    private val syncManager: SyncManager,
) {
    suspend fun execute(file: File, model: String): Result<Transcription> {
        // Step 1 — STT + persist raw transcript + save Original version
        val sttResult = transcriptionRepository.transcribe(file, model)
        sttResult.onFailure { return sttResult }

        val rawTranscription = sttResult.getOrThrow()
        if (rawTranscription.text.isBlank()) return Result.success(rawTranscription)

        // Step 2 — Only run AI pipeline when online (AI also requires internet)
        val isOnline = syncManager.isOnline.value
        val grammarEnabled     = prefs.grammarCorrectionEnabled && isOnline
        val autoEnhanceEnabled = prefs.autoEnhanceAfterTranscription && isOnline

        if (!isOnline) {
            Log.d(TAG, "Skipping AI pipeline — no internet connection")
            return Result.success(rawTranscription)
        }

        // Step 3 — Run AI pipeline; returns final display text
        val finalText = aiService.processPostTranscription(
            transcriptId       = rawTranscription.id,
            rawText            = rawTranscription.text,
            grammarEnabled     = grammarEnabled,
            autoEnhanceEnabled = autoEnhanceEnabled,
        )

        // Step 4 — Update transcription row if AI changed the text
        if (finalText != rawTranscription.text) {
            transcriptionRepository.updateText(rawTranscription.id, finalText)
            Log.d(TAG, "Updated transcription ${rawTranscription.id} display text after AI pipeline")
        }

        // Step 5 — Return updated Transcription
        return Result.success(
            if (finalText != rawTranscription.text) rawTranscription.copy(text = finalText)
            else rawTranscription
        )
    }

    companion object {
        private const val TAG = "ProcessTranscriptionUseCase"
    }
}
