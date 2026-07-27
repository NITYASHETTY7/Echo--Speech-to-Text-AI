package com.echo.dictation.domain.ai

import android.util.Log
import com.echo.dictation.data.local.AppPreferences
import com.echo.dictation.domain.model.Transcription
import com.echo.dictation.domain.repository.TranscriptionRepository
import com.echo.dictation.domain.session.SessionManager
import com.echo.dictation.domain.sync.SyncManager
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

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
 *  4. Immediately triggers a background upload to Firestore (non-blocking).
 *     If the upload fails it stays PENDING — WorkManager/NetworkCallback retries it later.
 *  5. Returns the updated [Transcription] to the caller.
 */
@Singleton
class ProcessTranscriptionUseCase @Inject constructor(
    private val transcriptionRepository: TranscriptionRepository,
    private val aiService: AIService,
    private val prefs: AppPreferences,
    private val syncManager: SyncManager,
    private val sessionManager: SessionManager,
) {
    // Unstructured scope kept intentionally: uploads must survive ViewModel cancellation.
    private val uploadScope = CoroutineScope(Dispatchers.IO)

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

        val finalTranscription: Transcription = if (!isOnline) {
            Log.d(TAG, "Skipping AI pipeline — no internet connection")
            rawTranscription
        } else {
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
                rawTranscription.copy(text = finalText)
            } else {
                rawTranscription
            }
        }

        // Step 5 — Immediately upload to Firestore if user is signed in and online.
        // Runs on a background coroutine so it never blocks the caller.
        // On failure the record stays syncStatus=PENDING and is retried by
        // NetworkCallback.onAvailable() and the periodic WorkManager job.
        if (isOnline && sessionManager.currentUser.value != null) {
            uploadScope.launch {
                Log.d(TAG, "Immediate upload triggered for ${finalTranscription.id}")
                syncManager.uploadPendingChanges()
                    .onSuccess { Log.d(TAG, "Immediate upload succeeded for ${finalTranscription.id}") }
                    .onFailure { ex -> Log.w(TAG, "Immediate upload failed (will retry): ${ex.message}") }
            }
        }

        return Result.success(finalTranscription)
    }

    companion object {
        private const val TAG = "ProcessTranscriptionUseCase"
    }
}
