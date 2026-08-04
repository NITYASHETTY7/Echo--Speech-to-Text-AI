package com.echo.dictation.service.overlay

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.util.Log
import android.widget.Toast
import com.echo.dictation.core.accessibility.TextInsertionHelper
import com.echo.dictation.core.accessibility.TextInsertionAccessibilityService
import com.echo.dictation.core.audio.AudioFileManager
import com.echo.dictation.core.audio.AudioRecorder
import com.echo.dictation.core.permission.PermissionManager
import com.echo.dictation.data.local.AppPreferences
import com.echo.dictation.domain.repository.TranscriptionRepository
import com.echo.dictation.speech.provider.ProviderRegistry
import com.echo.dictation.speech.provider.ProviderSettings
import com.echo.dictation.speech.provider.SpeechProviderFactory
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import com.echo.dictation.domain.ai.ProcessTranscriptionUseCase
import com.echo.dictation.domain.recording.RecordingEventBus
import javax.inject.Inject
import javax.inject.Singleton

sealed interface PillState {
    data object Idle : PillState
    data object Recording : PillState
    data object Transcribing : PillState
}

@Singleton
class PillController @Inject constructor(
    private val audioRecorder: AudioRecorder,
    private val audioFileManager: AudioFileManager,
    private val transcriptionRepository: TranscriptionRepository,
    private val processTranscriptionUseCase: ProcessTranscriptionUseCase,
    private val recordingEventBus: RecordingEventBus,
    private val preferences: AppPreferences,
    private val permissions: PermissionManager,
    private val textInsertionHelper: TextInsertionHelper,
    private val providerFactory: SpeechProviderFactory,
    private val providerSettings: ProviderSettings,
    private val syncManager: com.echo.dictation.domain.sync.SyncManager,
) {
    private val state = MutableStateFlow<PillState>(PillState.Idle)
    val pillState: StateFlow<PillState> = state.asStateFlow()

    /**
     * The coroutine scope used for all recording/transcription work.
     *
     * PillController is a @Singleton but PillOverlayService is not — the service
     * can be stopped and restarted while the controller instance lives on.
     * cleanup() cancels this scope; newScope() creates a fresh one so that
     * subsequent service starts work correctly without reconstructing the singleton.
     */
    private var scope = newScope()

    private fun newScope() = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    private var currentFile: File? = null

    @Volatile private var transcriptionJob: Job? = null

    var serviceContext: android.content.Context? = null

    fun toggleState() {
        Log.d(TAG, "toggleState() current=${state.value}")
        when (state.value) {
            is PillState.Idle         -> startRecordingInternal()
            is PillState.Recording    -> stopRecordingInternal()
            is PillState.Transcribing -> cancelTranscription()
        }
    }

    // ─── Start ───────────────────────────────────────────────────────────────

    private fun startRecordingInternal() {
        // Echo requires internet for Groq Whisper STT — block recording when offline
        if (!syncManager.isOnline.value) {
            showToast("Internet connection required to transcribe speech.")
            return
        }

        if (!permissions.hasRecordAudio()) {
            Log.e(TAG, "RECORD_AUDIO permission not granted")
            state.value = PillState.Idle
            showToast("Microphone permission required. Open Echo to grant it.")
            serviceContext?.let { ctx ->
                ctx.startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.fromParts("package", ctx.packageName, null)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                )
            }
            return
        }

        if (audioRecorder.recording.value) {
            Log.w(TAG, "startRecording — recorder still active, stopping first")
            audioRecorder.stop()
        }

        try {
            val outputFile = audioFileManager.newFile()
            currentFile = outputFile
            audioRecorder.start(outputFile)
            state.value = PillState.Recording
            Log.d(TAG, "Recording started: ${outputFile.name}")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start recording", e)
            showToast("Failed to start recording: ${e.message}")
            state.value = PillState.Idle
            currentFile = null
        }
    }

    // ─── Cancel ──────────────────────────────────────────────────────────────

    private fun cancelTranscription() {
        Log.d(TAG, "cancelTranscription()")
        if (audioRecorder.recording.value) audioRecorder.stop()
        currentFile = null
        val job = transcriptionJob
        if (job != null && job.isActive) {
            job.cancel(CancellationException("Cancelled by user tap"))
        } else {
            transcriptionJob = null
            state.value = PillState.Idle
        }
    }

    // ─── Stop → transcribe ────────────────────────────────────────────────────

    private fun stopRecordingInternal() {
        Log.d(TAG, "Stop recording requested")

        val nodeAtTapTime = TextInsertionAccessibilityService.instance?.lastEditableNode
        Log.d(TAG, "Node at tap: ${nodeAtTapTime?.packageName ?: "null"}")

        // Pre-flight: ensure the selected provider has a key configured
        if (!providerFactory.isCurrentProviderConfigured()) {
            val providerName = ProviderRegistry.getConfig(providerSettings.selectedProvider).displayName
            Log.e(TAG, "No API key configured for $providerName")
            showToast("No API key for $providerName. Open Echo → Settings to configure.")
            audioRecorder.stop()
            currentFile = null
            state.value = PillState.Idle
            return
        }

        state.value = PillState.Transcribing
        Log.d(TAG, "State → Transcribing")

        val job = scope.launch(Dispatchers.IO) {
            Log.d(TAG, "[IO] Coroutine started on ${Thread.currentThread().name}")
            try {
                Log.d(TAG, "[IO] Stopping recorder…")
                val recordingResult = audioRecorder.stop()
                Log.d(TAG, "[IO] Recorder stopped → ${
                    recordingResult?.let { "file=${it.file.name} peak=${it.peakAmplitude}" } ?: "null"
                }")

                if (recordingResult == null) {
                    Log.e(TAG, "[IO] No recording result")
                    withContext(Dispatchers.Main) { showToast("No audio captured. Try again.") }
                    return@launch
                }

                val (recordedFile, peakAmplitude) = recordingResult
                Log.d(TAG, "[IO] peak=$peakAmplitude  file=${recordedFile.name}  size=${recordedFile.length()}B")

                if (peakAmplitude < SILENCE_THRESHOLD) {
                    Log.w(TAG, "[IO] Silence — skipping")
                    recordedFile.delete()
                    withContext(Dispatchers.Main) { showToast("No speech detected.") }
                    return@launch
                }

                val model = preferences.model
                Log.d(TAG, "[IO] Sending to provider — file=${recordedFile.name} model=$model")

                val result = runCatching {
                    processTranscriptionUseCase.execute(recordedFile, model)
                }.getOrElse { t ->
                    Log.e(TAG, "[IO] Repository exception: ${t::class.java.name}: ${t.message}", t)
                    Result.failure(t)
                }

                Log.d(TAG, "[IO] Repository returned — isSuccess=${result.isSuccess}")

                withContext(Dispatchers.Main) {
                    result.fold(
                        onSuccess = { transcription ->
                            Log.d(TAG, "[Main] Transcription OK: '${transcription.text.take(80)}'")
                            if (transcription.text.isEmpty()) {
                                showToast("No speech detected.")
                            } else {
                                // Always emit to event bus FIRST — history updates regardless
                                // of whether text insertion or clipboard fallback is used.
                                scope.launch(Dispatchers.IO) {
                                    recordingEventBus.emitCompleted(transcription)
                                }
                                textInsertionHelper.insertTextIntoNode(
                                    text       = transcription.text,
                                    targetNode = nodeAtTapTime,
                                    showToast  = true,
                                )
                            }
                        },
                        onFailure = { error ->
                            Log.e(TAG, "[Main] Transcription failed: ${error::class.java.name}: ${error.message}", error)
                            val msg = when (error) {
                                is java.net.UnknownHostException   -> "No internet — cannot reach provider"
                                is java.net.SocketTimeoutException -> "Request timed out — check connection"
                                is javax.net.ssl.SSLException      -> "SSL error: ${error.message}"
                                is java.io.IOException             -> "Network error: ${error.message}"
                                else                               -> error.message ?: "Transcription failed"
                            }
                            showToast(msg)
                        }
                    )
                }

            } catch (ce: CancellationException) {
                Log.d(TAG, "[IO] Transcription cancelled: ${ce.message}")
                throw ce
            } catch (e: Exception) {
                Log.e(TAG, "[IO] Pipeline exception: ${e::class.java.name}: ${e.message}", e)
                withContext(Dispatchers.Main) { showToast("Error: ${e.message}") }
            } finally {
                Log.d(TAG, "[IO] finally — cleaning up")
                if (audioRecorder.recording.value) audioRecorder.stop()
                transcriptionJob = null
                currentFile = null
                try {
                    withContext(Dispatchers.Main.immediate) {
                        state.value = PillState.Idle
                        Log.d(TAG, "[Main] State → Idle ✓")
                    }
                } catch (ce: CancellationException) {
                    Log.e(TAG, "[finally] scope cancelled, forcing Idle directly")
                    state.value = PillState.Idle
                }
            }
        }
        transcriptionJob = job
        Log.d(TAG, "transcriptionJob assigned: $job")
    }

    // ─── Toast ───────────────────────────────────────────────────────────────

    private fun showToast(message: String) {
        val ctx = serviceContext ?: return
        scope.launch(Dispatchers.Main) {
            Toast.makeText(ctx, message, Toast.LENGTH_SHORT).show()
        }
    }

    // ─── Lifecycle ────────────────────────────────────────────────────────────

    fun cleanup() {
        Log.d(TAG, "cleanup() called")
        if (audioRecorder.recording.value) audioRecorder.stop()
        transcriptionJob?.cancel(CancellationException("Service destroyed"))
        transcriptionJob = null
        currentFile = null
        state.value = PillState.Idle
        serviceContext = null
        // Cancel the old scope, then immediately create a fresh one.
        // PillController is a @Singleton — the same instance is reused every time
        // PillOverlayService starts. Without this, scope.launch() produces a job
        // in {Cancelling} state and the coroutine body never executes.
        scope.cancel()
        scope = newScope()
        Log.d(TAG, "cleanup() done — fresh scope ready for next service start")
    }

    companion object {
        private const val TAG = "PillController"
        private const val SILENCE_THRESHOLD = 1500
    }
}
