package com.echo.dictation.core.audio

import android.content.Context
import android.media.MediaRecorder
import android.os.Build
import android.util.Log
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Result returned by [AudioRecorder.stop].
 * [peakAmplitude] is the highest value seen across all amplitude polls during recording
 * (range 0–32767). Callers use this to detect silence before sending to Whisper.
 */
data class RecordingResult(val file: File, val peakAmplitude: Int)

@Singleton
class AudioRecorder @Inject constructor(@ApplicationContext private val context: Context) {
    private var recorder: MediaRecorder? = null
    private var file: File? = null
    private val _recording = MutableStateFlow(false)
    val recording: StateFlow<Boolean> = _recording.asStateFlow()

    // Peak amplitude accumulated across all polls during a recording session.
    // Written only from the amplitude-polling coroutine; read in stop() on IO thread.
    @Volatile private var sessionPeak: Int = 0

    private val amplitudeScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var amplitudeJob: Job? = null

    @Synchronized
    fun start(output: File) {
        Log.d(TAG, "start() → ${output.name}")
        check(recorder == null) { "Recording already active" }

        output.parentFile?.let { parent ->
            if (!parent.exists()) check(parent.mkdirs() || parent.exists()) {
                "Unable to create audio directory"
            }
        }

        val mediaRecorder = if (Build.VERSION.SDK_INT >= 31) MediaRecorder(context)
        else @Suppress("DEPRECATION") MediaRecorder()

        try {
            try {
                mediaRecorder.setAudioSource(MediaRecorder.AudioSource.VOICE_RECOGNITION)
            } catch (e: Exception) {
                Log.w(TAG, "VOICE_RECOGNITION unavailable, falling back to MIC", e)
                mediaRecorder.setAudioSource(MediaRecorder.AudioSource.MIC)
            }
            mediaRecorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            mediaRecorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            mediaRecorder.setAudioSamplingRate(SAMPLE_RATE_HZ)
            mediaRecorder.setAudioEncodingBitRate(BIT_RATE)
            mediaRecorder.setAudioChannels(CHANNELS)
            mediaRecorder.setOutputFile(output.absolutePath)
            mediaRecorder.prepare()
            mediaRecorder.start()
        } catch (e: Throwable) {
            Log.e(TAG, "Recorder init failed", e)
            mediaRecorder.release()
            throw e
        }

        recorder = mediaRecorder
        file = output
        sessionPeak = 0
        _recording.value = true

        // Poll amplitude every 200 ms and accumulate the session peak.
        amplitudeJob = amplitudeScope.launch {
            while (isActive) {
                delay(AMPLITUDE_POLL_MS)
                val amp = try { mediaRecorder.maxAmplitude } catch (_: Exception) { 0 }
                if (amp > sessionPeak) sessionPeak = amp
            }
        }
        Log.d(TAG, "Recording started, polling amplitude every ${AMPLITUDE_POLL_MS}ms")
    }

    @Synchronized
    fun stop(): RecordingResult? {
        Log.d(TAG, "stop() called")
        amplitudeJob?.cancel()
        amplitudeJob = null

        val activeRecorder = recorder ?: run {
            Log.w(TAG, "Recorder is null, nothing to stop")
            return null
        }

        // One final poll to catch any peak between the last scheduled poll and now.
        try {
            val lastAmp = activeRecorder.maxAmplitude
            if (lastAmp > sessionPeak) sessionPeak = lastAmp
        } catch (_: Exception) {}

        val peak = sessionPeak
        val output = file
        var savedFile: File? = null

        try {
            activeRecorder.stop()
            activeRecorder.release()

            if (output != null && output.isFile && output.length() > 0L) {
                savedFile = output
                Log.d(TAG, "Saved: ${output.name}  size=${output.length()} B  peak=$peak")
            } else {
                Log.e(TAG, "Output file missing or empty")
                output?.delete()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping recorder", e)
            try { activeRecorder.release() } catch (_: Exception) {}
            output?.delete()
        } finally {
            recorder = null
            file = null
            sessionPeak = 0
            _recording.value = false
        }

        return savedFile?.let { RecordingResult(it, peak) }
    }

    companion object {
        private const val TAG = "AudioRecorder"
        private const val SAMPLE_RATE_HZ = 16_000
        private const val BIT_RATE = 128_000
        private const val CHANNELS = 1
        private const val AMPLITUDE_POLL_MS = 200L
    }
}
