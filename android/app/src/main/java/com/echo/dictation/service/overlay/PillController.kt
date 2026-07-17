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
import com.echo.dictation.core.audio.RecordingResult
import com.echo.dictation.core.permission.PermissionManager
import com.echo.dictation.data.local.AppPreferences
import com.echo.dictation.domain.repository.TranscriptionRepository
import com.echo.dictation.speech.GroqApiKeyStore
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
    private val preferences: AppPreferences,
    private val permissions: PermissionManager,
    private val textInsertionHelper: TextInsertionHelper,
    private val groqApiKeyStore: GroqApiKeyStore,
) {
    private val state = MutableStateFlow<PillState>(PillState.Idle)
    val pillState: StateFlow<PillState> = state.asStateFlow()

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var currentFile: File? = null

    /** Set by PillOverlayService so we can post Toasts from a service context. */
    var serviceContext: android.content.Context? = null

    fun toggleState() {
        when (state.value) {
            is PillState.Idle        -> startRecording()
            is PillState.Recording   -> stopRecording()
            is PillState.Transcribing -> showToast("Still transcribing, please wait…")
        }
    }

    // ─── Start ───────────────────────────────────────────────────────────────

    private fun startRecording() {
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
            Log.w(TAG, "Recorder still active, ignoring duplicate start")
            state.value = PillState.Idle
            return
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

    // ─── Stop ────────────────────────────────────────────────────────────────

    private fun stopRecording() {
        Log.d(TAG, "Stop recording requested")

        // Capture the focused node synchronously on the Main thread NOW, before the
        // network call clears FOCUS_INPUT from the target app's window.
        val nodeAtTapTime = TextInsertionAccessibilityService.instance?.lastEditableNode
        Log.d(TAG, "Node at tap: ${nodeAtTapTime?.packageName ?: "null"}")

        // Pre-flight: reject immediately if no API key is configured.
        if (!groqApiKeyStore.isConfigured) {
            Log.e(TAG, "No Groq API key configured")
            showToast("No Groq API key saved. Open Echo → Settings to add your key.")
            audioRecorder.stop()
            currentFile = null
            state.value = PillState.Idle
            return
        }

        state.value = PillState.Transcribing

        scope.launch(Dispatchers.IO) {
            try {
                // Stop recorder — returns file + peak amplitude accumulated during recording.
                val recordingResult = audioRecorder.stop()

                if (recordingResult == null) {
                    Log.e(TAG, "No recording result — file missing or recorder failed")
                    withContext(Dispatchers.Main) { showToast("No audio captured. Try again.") }
                    return@launch
                }

                val (recordedFile, peakAmplitude) = recordingResult
                Log.d(TAG, "peak=$peakAmplitude  file=${recordedFile.name}  size=${recordedFile.length()}B")

                // ── Silence gate ──────────────────────────────────────────────
                // MediaRecorder amplitude range is 0–32767.
                // Empirical threshold: true silence ≈ 0–150; breathing/room noise ≈ 150–500;
                // quiet speech starts around 500–800; normal speech 1000+.
                // We reject anything below 500 to avoid sending silence to Whisper.
                if (peakAmplitude < SILENCE_THRESHOLD) {
                    Log.w(TAG, "Peak $peakAmplitude < threshold $SILENCE_THRESHOLD — silence, skipping")
                    recordedFile.delete()
                    withContext(Dispatchers.Main) { showToast("No speech detected.") }
                    return@launch
                }

                // ── Send to Whisper ───────────────────────────────────────────
                Log.d(TAG, "Speech detected (peak=$peakAmplitude), sending to server")
                val model = preferences.model
                val result = transcriptionRepository.transcribe(recordedFile, model)

                withContext(Dispatchers.Main) {
                    result.fold(
                        onSuccess = { transcription ->
                            Log.d(TAG, "Transcription OK: ${transcription.text.take(80)}")
                            if (transcription.text.isEmpty()) {
                                Log.w(TAG, "Transcription discarded as hallucination — no speech inserted")
                                showToast("No speech detected.")
                            } else {
                                textInsertionHelper.insertTextIntoNode(
                                    text       = transcription.text,
                                    targetNode = nodeAtTapTime,
                                    showToast  = true
                                )
                            }
                        },
                        onFailure = { error ->
                            Log.e(TAG, "Transcription failed: ${error.message}", error)
                            showToast("Transcription failed: ${error.message}")
                        }
                    )
                }

            } catch (e: Exception) {
                Log.e(TAG, "Pipeline error: ${e.message}", e)
                withContext(Dispatchers.Main) { showToast("Error: ${e.message}") }
            } finally {
                // Always reset — success, failure, silence, or exception.
                currentFile = null
                withContext(Dispatchers.Main) { state.value = PillState.Idle }
            }
        }
    }

    // ─── Toast helper ────────────────────────────────────────────────────────

    private fun showToast(message: String) {
        val ctx = serviceContext ?: return
        scope.launch(Dispatchers.Main) {
            Toast.makeText(ctx, message, Toast.LENGTH_SHORT).show()
        }
    }

    // ─── Lifecycle ───────────────────────────────────────────────────────────

    fun cleanup() {
        if (state.value is PillState.Recording) audioRecorder.stop()
        state.value = PillState.Idle   // also covers Transcribing
        serviceContext = null
        scope.cancel()
    }

    companion object {
        private const val TAG = "PillController"

        /**
         * Minimum peak amplitude required to consider a recording as containing speech.
         * MediaRecorder.getMaxAmplitude() range: 0–32767.
         * Dead silence ≈ 0–150; room noise/breathing ≈ 150–800; quiet speech ≈ 800–2000;
         * normal speech 2000+. 1500 reliably rejects noise/breathing while accepting
         * even quiet whispered speech.
         */
        private const val SILENCE_THRESHOLD = 1500
    }
}
