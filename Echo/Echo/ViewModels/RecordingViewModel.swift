//
//  RecordingViewModel.swift
//  Echo
//
//  ViewModel that drives the recording → transcription flow.
//
//  Owns an AudioRecorder and a TranscriptionCoordinator. The recorder's
//  onStateChange callback keeps recordingState in sync. After the recorder
//  completes, TranscriptionCoordinator.transcribe(recording:) is invoked
//  automatically and its onStateChange callback mirrors CoordinatorState
//  into transcriptionState.
//
//  A metering timer is managed here (rather than inside AudioRecorder) so
//  the UI can bind to a single, smoothed audioLevel property.
//

import Foundation
import EchoCore
import AVFoundation
import os

@MainActor
@Observable
public final class RecordingViewModel: Identifiable {

    // MARK: - Identifiable

    /// Stable identity for use as a SwiftUI sheet `item` binding.
    /// Each recording session gets a new UUID so a fresh RecordingView is
    /// always presented after the previous session is dismissed.
    public let id = UUID()

    // MARK: - Public state

    /// Current recording lifecycle state (mirrors AudioRecorder.state).
    private(set) var recordingState: RecordingState = .idle

    /// Current transcription lifecycle state (mirrors CoordinatorState).
    private(set) var transcriptionState: CoordinatorState = .idle

    /// Elapsed recording duration in seconds; updated by metering poll.
    private(set) var duration: TimeInterval = 0

    /// Normalised audio level in 0…1; updated at meteringInterval.
    private(set) var audioLevel: Float = 0

    /// Non-nil when a terminal error should be surfaced to the UI.
    private(set) var recordingError: RecordingError?

    /// Non-nil when a transcription error should be surfaced to the UI.
    private(set) var transcriptionError: TranscriptionError?

    /// Convenience: is the microphone actively capturing audio?
    var isRecording: Bool {
        if case .recording = recordingState { return true }
        return false
    }

    /// Convenience: is the recorder paused?
    var isPaused: Bool {
        if case .paused = recordingState { return true }
        return false
    }

    /// Convenience: is a transcription in flight?
    var isTranscribing: Bool {
        if case .transcribing = transcriptionState { return true }
        return false
    }

    /// The most recent completed TranscriptionResponse, if any.
    private(set) var lastTranscriptionResponse: TranscriptionResponse?

    // MARK: - Private services

    private let recorder: AudioRecorder
    private let coordinator: TranscriptionCoordinator

    // MARK: - Metering

    private var meteringTimer: Timer?
    private let meteringInterval: TimeInterval = 0.1   // 100 ms, matches Android 200 ms / 2

    // MARK: - Init

    init(recorder: AudioRecorder, coordinator: TranscriptionCoordinator) {
        self.recorder = recorder
        self.coordinator = coordinator
        wireCallbacks()
    }

    // MARK: - Callback wiring

    private func wireCallbacks() {
        // AudioRecorder → recordingState
        recorder.onStateChange = { [weak self] newState in
            guard let self else { return }
            self.recordingState = newState

            switch newState {
            case .recording:
                self.startMeteringTimer()
            case .paused:
                self.stopMeteringTimer()
            case .stopping, .idle:
                self.stopMeteringTimer()
                self.duration = 0
                self.audioLevel = 0
            case .failed(let error):
                self.stopMeteringTimer()
                self.recordingError = error
                EchoLog.ui.error("Recording failed: \(error.localizedDescription, privacy: .public)")
            case .completed(let result):
                self.stopMeteringTimer()
                self.duration = result.duration
                self.audioLevel = 0
                // Kick off transcription automatically.
                self.coordinator.transcribe(recording: result)
            default:
                break
            }
        }

        // TranscriptionCoordinator → transcriptionState
        coordinator.onStateChange = { [weak self] newState in
            guard let self else { return }
            self.transcriptionState = newState

            switch newState {
            case .completed(let response):
                self.lastTranscriptionResponse = response
                EchoLog.ui.debug("Transcription completed: \(response.text.prefix(80), privacy: .public)")
            case .failed(let error):
                self.transcriptionError = error
                EchoLog.ui.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
            default:
                break
            }
        }
    }

    // MARK: - Public recording controls

    /// Requests microphone permission if not yet granted, then starts recording.
    func startRecording() async {
        recordingError = nil
        transcriptionError = nil
        lastTranscriptionResponse = nil

        // If we haven't got permission yet, request it first.
        if case .idle = recordingState {
            let granted = await recorder.requestPermission()
            guard granted else { return }
        }

        do {
            try await recorder.startRecording()
        } catch let error as RecordingError {
            recordingError = error
        } catch {
            recordingError = .recordingFailed(reason: error.localizedDescription)
        }
    }

    func pauseRecording() {
        recorder.pauseRecording()
    }

    func resumeRecording() {
        recorder.resumeRecording()
    }

    /// Stops the active recording and hands off to TranscriptionCoordinator.
    func stopRecording() async {
        do {
            _ = try await recorder.stopRecording()
            // TranscriptionCoordinator.transcribe is triggered via the
            // onStateChange(.completed) callback above.
        } catch let error as RecordingError {
            recordingError = error
        } catch {
            recordingError = .recordingFailed(reason: error.localizedDescription)
        }
    }

    /// Cancels the recording; any partial file is discarded.
    func cancelRecording() {
        recorder.cancelRecording()
        coordinator.cancel()
        stopMeteringTimer()
        duration = 0
        audioLevel = 0
    }

    /// Cancels any in-progress transcription (does not affect recording).
    func cancelTranscription() {
        coordinator.cancel()
    }

    /// Called when the app moves to the background while recording.
    /// Stops the metering timer to avoid unnecessary CPU use; the recorder
    /// continues in the background as long as the audio session permits it.
    /// If the system interrupts the session, AudioSessionManager will call
    /// the delegate which stops the recording via the existing interrupt path.
    func handleSceneBackground() {
        // Stop the UI metering timer — the underlying recorder keeps running.
        stopMeteringTimer()
        EchoLog.audio.debug("Scene backgrounded — metering timer stopped")
    }

    /// Called when the app returns to the foreground.
    /// Restarts the metering timer so the UI reflects live levels again.
    func handleSceneForeground() {
        guard case .recording = recordingState else { return }
        startMeteringTimer()
        EchoLog.audio.debug("Scene foregrounded — metering timer restarted")
    }

    // MARK: - Metering timer

    private func startMeteringTimer() {
        stopMeteringTimer()
        meteringTimer = Timer.scheduledTimer(
            withTimeInterval: meteringInterval,
            repeats: true
        ) { [weak self] _ in
            guard let vm = self else { return }
            Task { @MainActor in
                vm.updateMetering()
            }
        }
    }

    private func stopMeteringTimer() {
        meteringTimer?.invalidate()
        meteringTimer = nil
    }

    /// Reads the current metering from the recorder and updates duration + audioLevel.
    private func updateMetering() {
        if case .recording = recordingState {
            duration += meteringInterval
        }

        guard case .recording = recordingState else {
            audioLevel = 0
            return
        }

        // Convert dBFS power from AVAudioRecorder to a 0–1 linear scale.
        // dBFS range is roughly -160 (silence) to 0 (full scale).
        // We clamp to a useful voice range: -60 dBFS (very quiet) → 0 dBFS (loud).
        let db = Double(recorder.currentPowerDB)
        let minDB: Double = -60.0
        let clamped = max(minDB, min(0.0, db))
        let linear = Float((clamped - minDB) / (0.0 - minDB))   // 0…1
        // Smooth the reading slightly so the meter doesn't flicker.
        audioLevel = audioLevel * 0.6 + linear * 0.4
    }
}
