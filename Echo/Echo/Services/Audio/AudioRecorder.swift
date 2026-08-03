//
//  AudioRecorder.swift
//  Echo
//
//  Records microphone input using AVAudioRecorder.  The recorder owns its
//  state machine; AVAudioSession is managed externally by AudioSessionManager.
//
//  Android source of truth:
//    AudioRecorder.kt — AAC/m4a, 16 kHz mono, 200 ms amplitude polling,
//                       sessionPeak tracking, start/stop/release lifecycle.
//

import Foundation
import AVFoundation
import os

// MARK: - AVAudioRecorder protocol (testability boundary)

protocol AVAudioRecorderProtocol: AnyObject {
    var isRecording: Bool { get }
    var currentTime: TimeInterval { get }
    var isMeteringEnabled: Bool { get set }
    func prepareToRecord() -> Bool
    func record() -> Bool
    func pause()
    func stop()
    func deleteRecording() -> Bool
    func averagePower(forChannel channelNumber: Int) -> Float
    func peakPower(forChannel channelNumber: Int) -> Float
    func updateMeters()
}

extension AVAudioRecorder: AVAudioRecorderProtocol {}

// MARK: - AVAudioRecorder factory (testability boundary)

typealias AVAudioRecorderFactory = (URL, [String: Any]) throws -> AVAudioRecorderProtocol

// MARK: - AudioRecorder

@MainActor
final class AudioRecorder: NSObject {

    // MARK: - Published state

    internal(set) var state: RecordingState = .idle {
        didSet {
            EchoLog.audio.debug("AudioRecorder state: \(String(describing: self.state), privacy: .public)")
            onStateChange?(state)
        }
    }

    /// Called on the main actor whenever state changes.
    var onStateChange: ((RecordingState) -> Void)?

    /// The most recently measured average power in dBFS (-160…0).
    /// Updated every `configuration.meteringInterval` while recording.
    /// Consumers can convert to a 0–1 linear level via: pow(10, value/20).
    private(set) var currentPowerDB: Float = -160

    // MARK: - Dependencies

    private let configuration: RecordingConfiguration
    private let fileManager: AudioFileManager
    private let sessionManager: AudioSessionManaging
    private let recorderFactory: AVAudioRecorderFactory

    // MARK: - Mutable recording state

    private var activeRecorder: AVAudioRecorderProtocol?
    private var currentFileURL: URL?
    private var recordingStartDate: Date?
    private var meteringTimer: Timer?
    /// Peak power in dB accumulated across all polls (most negative dBFS is silence).
    private var sessionPeakDB: Float = -160

    // MARK: - Init

    init(
        configuration: RecordingConfiguration = .standard,
        fileManager: AudioFileManager? = nil,
        sessionManager: AudioSessionManaging? = nil,
        recorderFactory: AVAudioRecorderFactory? = nil
    ) {
        self.configuration = configuration
        self.fileManager = fileManager ?? AudioFileManager(configuration: configuration)
        self.sessionManager = sessionManager ?? AudioSessionManager()
        self.recorderFactory = recorderFactory ?? { url, settings in
            try AVAudioRecorder(url: url, settings: settings)
        }
        super.init()
        (self.sessionManager as? AudioSessionManager)?.delegate = self
    }

    // MARK: - Permission

    func requestPermission() async -> Bool {
        state = .requestingPermission
        let granted = await sessionManager.requestPermission()
        state = granted ? .ready : .failed(.permissionDenied)
        return granted
    }

    // MARK: - Start

    func startRecording() async throws {
        guard state.canStart else {
            EchoLog.audio.warning("startRecording() ignored — state is \(String(describing: self.state), privacy: .public)")
            return
        }

        // Activate audio session.
        do {
            try sessionManager.activate()
        } catch let error as RecordingError {
            state = .failed(error)
            throw error
        }

        // Prepare output file.
        let fileURL: URL
        do {
            fileURL = try fileManager.newRecordingURL()
        } catch {
            sessionManager.deactivate()
            let re = RecordingError.recorderSetupFailed(reason: error.localizedDescription)
            state = .failed(re)
            throw re
        }

        // Create and start recorder.
        let recorder: AVAudioRecorderProtocol
        do {
            recorder = try recorderFactory(fileURL, configuration.avSettings)
        } catch {
            sessionManager.deactivate()
            fileManager.delete(fileURL: fileURL)
            let re = RecordingError.recorderSetupFailed(reason: error.localizedDescription)
            state = .failed(re)
            throw re
        }

        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record() else {
            sessionManager.deactivate()
            fileManager.delete(fileURL: fileURL)
            let re = RecordingError.recorderSetupFailed(reason: "prepareToRecord/record returned false")
            state = .failed(re)
            throw re
        }

        activeRecorder = recorder
        currentFileURL = fileURL
        recordingStartDate = .now
        sessionPeakDB = -160
        startMeteringTimer()
        state = .recording
    }

    // MARK: - Stop

    func stopRecording() async throws -> RecordingResult {
        guard state.canStop else {
            EchoLog.audio.warning("stopRecording() ignored — state is \(String(describing: self.state), privacy: .public)")
            throw RecordingError.recordingFailed(reason: "No active recording")
        }

        state = .stopping
        return try await finishRecording(cancelled: false)
    }

    // MARK: - Pause / Resume

    func pauseRecording() {
        guard state.canPause, let recorder = activeRecorder else { return }
        stopMeteringTimer()
        recorder.pause()
        state = .paused
    }

    func resumeRecording() {
        guard state.canResume, let recorder = activeRecorder else { return }
        guard recorder.record() else {
            state = .failed(.recordingFailed(reason: "resume returned false"))
            cleanup(deleteFile: false)
            return
        }
        startMeteringTimer()
        state = .recording
    }

    // MARK: - Cancel

    func cancelRecording() {
        stopMeteringTimer()
        guard let fileURL = currentFileURL else {
            activeRecorder?.stop()
            activeRecorder = nil
            sessionManager.deactivate()
            state = .idle
            return
        }
        activeRecorder?.stop()
        activeRecorder?.deleteRecording()
        activeRecorder = nil
        fileManager.delete(fileURL: fileURL)
        currentFileURL = nil
        recordingStartDate = nil
        sessionPeakDB = -160
        sessionManager.deactivate()
        state = .idle
        EchoLog.audio.debug("Recording cancelled")
    }

    // MARK: - Internal finish

    private func finishRecording(cancelled: Bool) async throws -> RecordingResult {
        stopMeteringTimer()

        guard let recorder = activeRecorder, let fileURL = currentFileURL else {
            cleanup(deleteFile: cancelled)
            throw RecordingError.recordingFailed(reason: "Recorder or file URL is nil at finish")
        }

        // Take the final peak reading before stopping.
        recorder.updateMeters()
        let finalPeak = recorder.peakPower(forChannel: 0)
        if finalPeak > sessionPeakDB { sessionPeakDB = finalPeak }

        let duration = recordingStartDate.map { Date().timeIntervalSince($0) } ?? recorder.currentTime
        recorder.stop()
        activeRecorder = nil
        sessionManager.deactivate()

        // Verify file was written.
        let size = fileManager.fileSize(at: fileURL)
        guard size > 0 else {
            fileManager.delete(fileURL: fileURL)
            currentFileURL = nil
            let error = RecordingError.fileEmpty
            state = .failed(error)
            throw error
        }

        let result = RecordingResult(
            fileURL: fileURL,
            duration: duration,
            fileSize: size,
            format: "m4a",
            sampleRate: configuration.sampleRate,
            peakPowerDB: sessionPeakDB
        )

        currentFileURL = nil
        recordingStartDate = nil
        sessionPeakDB = -160
        state = .completed(result)
        EchoLog.audio.debug("Recording completed: \(fileURL.lastPathComponent, privacy: .public) size=\(size) duration=\(String(format: "%.1f", duration))s")
        return result
    }

    // MARK: - Metering

    private func startMeteringTimer() {
        stopMeteringTimer()
        meteringTimer = Timer.scheduledTimer(
            withTimeInterval: configuration.meteringInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.pollAmplitude() }
        }
    }

    private func stopMeteringTimer() {
        meteringTimer?.invalidate()
        meteringTimer = nil
    }

    private func pollAmplitude() {
        guard let recorder = activeRecorder, recorder.isRecording else { return }
        recorder.updateMeters()
        let peak = recorder.peakPower(forChannel: 0)
        currentPowerDB = peak
        if peak > sessionPeakDB { sessionPeakDB = peak }
    }

    // MARK: - Cleanup helpers

    private func cleanup(deleteFile: Bool) {
        stopMeteringTimer()
        activeRecorder?.stop()
        activeRecorder = nil
        if deleteFile, let url = currentFileURL {
            fileManager.delete(fileURL: url)
        }
        currentFileURL = nil
        recordingStartDate = nil
        sessionPeakDB = -160
        currentPowerDB = -160
        sessionManager.deactivate()
    }
}

// MARK: - AudioSessionDelegate

extension AudioRecorder: AudioSessionDelegate {

    nonisolated func audioSessionWasInterrupted(shouldResume: Bool) {
        Task { @MainActor in
            EchoLog.audio.debug("Session interrupted shouldResume=\(shouldResume, privacy: .public)")
            switch state {
            case .recording, .paused:
                if shouldResume {
                    // System said we can resume — try to resume.
                    resumeRecording()
                } else {
                    // Interruption began or won't resume — stop the recording.
                    state = .stopping
                    let _ = try? await finishRecording(cancelled: false)
                }
            default:
                break
            }
        }
    }

    nonisolated func audioRouteDidChange(reason: AVAudioSession.RouteChangeReason) {
        Task { @MainActor in
            EchoLog.audio.debug("Route changed: \(reason.rawValue, privacy: .public)")
            // When the old device was disconnected, Android lets recording continue
            // on the new route; we mirror that behaviour by taking no action.
            // A truly fatal route change (e.g. no input available) will surface as
            // an AVAudioRecorderDelegate error handled below.
            switch reason {
            case .oldDeviceUnavailable:
                // Headphones unplugged — the system automatically switches to the
                // built-in microphone; nothing to do.
                EchoLog.audio.debug("Old device unavailable — continuing on new route")
            default:
                break
            }
        }
    }

    nonisolated func audioSessionWasReset() {
        Task { @MainActor in
            EchoLog.audio.warning("Media services were reset")
            cleanup(deleteFile: true)
            state = .failed(.recordingFailed(reason: "Media services were reset"))
        }
    }
}

// MARK: - AVAudioRecorderDelegate

extension AudioRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderEncodeErrorDidOccur(
        _ recorder: AVAudioRecorder,
        error: Error?
    ) {
        let message = error?.localizedDescription ?? "unknown encode error"
        EchoLog.audio.error("Recorder encode error: \(message, privacy: .public)")
        Task { @MainActor in
            cleanup(deleteFile: true)
            state = .failed(.recordingFailed(reason: message))
        }
    }
}
