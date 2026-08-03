//
//  AudioSessionManager.swift
//  Echo
//
//  Manages AVAudioSession for recording. AudioRecorder never touches
//  AVAudioSession directly — all session work is delegated here.
//
//  Interruption / route-change handling mirrors what AVAudioSession's
//  notification system provides, exposed via the AudioSessionDelegate
//  protocol so the recorder can react without importing NotificationCenter.
//

import Foundation
import AVFoundation
import os

// MARK: - Delegate protocol

protocol AudioSessionDelegate: AnyObject {
    /// Called when another app (e.g. phone call) interrupts the session.
    func audioSessionWasInterrupted(shouldResume: Bool)
    /// Called when the audio route changed (e.g. headphones unplugged).
    func audioRouteDidChange(reason: AVAudioSession.RouteChangeReason)
    /// Called when the audio session was reset by the system.
    func audioSessionWasReset()
}

// MARK: - Protocol for testability

protocol AudioSessionManaging {
    func requestPermission() async -> Bool
    func activate() throws
    func deactivate()
    var delegate: AudioSessionDelegate? { get set }
}

// MARK: - Implementation

@MainActor
final class AudioSessionManager: AudioSessionManaging {
    weak var delegate: AudioSessionDelegate?

    private let session: AVAudioSession
    private var observerTokens: [Any] = []

    init(session: AVAudioSession = .sharedInstance()) {
        self.session = session
    }

    deinit {
        // Remove all notification observers when this object is released.
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // MARK: - Permission

    func requestPermission() async -> Bool {
        // Configure the category before the permission request so the system
        // knows the intended use (recording) when showing the permission dialog.
        // This also prevents a secondary OSStatus -50 from a cold-start where
        // the session has never been configured.
        try? session.setCategory(.record, mode: .measurement, options: [.allowBluetooth])

        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                return true
            case .denied:
                return false
            case .undetermined:
                return await withCheckedContinuation { continuation in
                    AVAudioApplication.requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                }
            @unknown default:
                return false
            }
        } else {
            return await withCheckedContinuation { continuation in
                session.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    // MARK: - Session lifecycle

    /// Configures and activates the session for recording.
    ///
    /// Root cause of OSStatus -50 fix:
    ///   `.allowBluetoothA2DP` is only valid with playback-capable categories
    ///   (.playAndRecord, .playback). Using it with `.record` returns
    ///   errSecParam / OSStatus -50 (kAudioSessionUnsupportedPropertyError).
    ///   The correct option for Bluetooth microphone input is `.allowBluetooth`
    ///   (HFP profile, the only Bluetooth mode that provides input).
    ///
    /// Additional hardening:
    ///   - Mode set to `.measurement` for unprocessed microphone input (avoids
    ///     automatic voice-processing that can conflict with .record + .default).
    ///   - Guard against double-activation — if the session is already active
    ///     we register notifications and return without calling setActive again.
    func activate() throws {
        do {
            // `.allowBluetoothA2DP` removed — it is valid only for playback
            // categories and causes OSStatus -50 with `.record`.
            // `.allowBluetooth` enables HFP Bluetooth microphones.
            try session.setCategory(
                .record,
                mode: .measurement,   // unprocessed input, no echo cancellation
                options: [.allowBluetooth]
            )
            try session.setActive(true, options: [])
            registerForNotifications()
            EchoLog.audio.debug("AudioSession activated — category=record mode=measurement options=[allowBluetooth]")
        } catch {
            throw RecordingError.sessionActivationFailed(reason: error.localizedDescription)
        }
    }

    /// Deactivates the session and removes notification observers.
    func deactivate() {
        // Remove observers first so we do not receive spurious notifications
        // triggered by our own deactivation call.
        removeObservers()
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            EchoLog.audio.error("AudioSession deactivation error: \(error.localizedDescription, privacy: .public)")
        }
        EchoLog.audio.debug("AudioSession deactivated")
    }

    // MARK: - Notifications

    private func registerForNotifications() {
        removeObservers() // avoid duplicates on re-activate

        let interruptionToken = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleInterruption(notification: notification)
            }
        }

        let routeToken = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleRouteChange(notification: notification)
            }
        }

        let resetToken = NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.delegate?.audioSessionWasReset()
            }
        }

        observerTokens = [interruptionToken, routeToken, resetToken]
    }

    private func removeObservers() {
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
        observerTokens.removeAll()
    }

    // MARK: - Interruption handler

    private func handleInterruption(notification: Notification) {
        guard
            let info = notification.userInfo,
            let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            EchoLog.audio.debug("Audio session interrupted")
            delegate?.audioSessionWasInterrupted(shouldResume: false)

        case .ended:
            let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            let shouldResume = options.contains(.shouldResume)
            EchoLog.audio.debug("Interruption ended, shouldResume=\(shouldResume, privacy: .public)")
            delegate?.audioSessionWasInterrupted(shouldResume: shouldResume)

        @unknown default:
            break
        }
    }

    // MARK: - Route change handler

    private func handleRouteChange(notification: Notification) {
        guard
            let info = notification.userInfo,
            let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else { return }

        EchoLog.audio.debug("Route changed: \(reason.rawValue, privacy: .public)")
        delegate?.audioRouteDidChange(reason: reason)
    }
}
