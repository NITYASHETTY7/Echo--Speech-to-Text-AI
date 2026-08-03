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

public protocol AudioSessionDelegate: AnyObject {
    /// Called when another app (e.g. phone call) interrupts the session.
    func audioSessionWasInterrupted(shouldResume: Bool)
    /// Called when the audio route changed (e.g. headphones unplugged).
    func audioRouteDidChange(reason: AVAudioSession.RouteChangeReason)
    /// Called when the audio session was reset by the system.
    func audioSessionWasReset()
}

// MARK: - Protocol for testability

public protocol AudioSessionManaging {
    func requestPermission() async -> Bool
    func activate() throws
    func deactivate()
    var delegate: AudioSessionDelegate? { get set }
}

// MARK: - Implementation

@MainActor
public final class AudioSessionManager: AudioSessionManaging {
    public weak var delegate: AudioSessionDelegate?

    private let session: AVAudioSession
    private var observerTokens: [Any] = []

    public init(session: AVAudioSession = .sharedInstance()) {
        self.session = session
    }

    deinit {
        // Remove all notification observers when this object is released.
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // MARK: - Permission

    public func requestPermission() async -> Bool {
        // Pre-configure the session category BEFORE showing the permission dialog
        // so iOS knows the intended use. This prevents a secondary OSStatus -50
        // on the first activation after a cold start.
        // Mode is .default (not .measurement) so the AAC encoder's sample-rate
        // conversion path is available — see activate() for the full rationale.
        try? session.setCategory(.record, mode: .default, options: [.allowBluetooth])

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

    /// Configures and activates the AVAudioSession for recording.
    ///
    /// OSStatus -50 root cause and fix:
    ///   `.allowBluetoothA2DP` is only valid for playback-capable categories
    ///   (`.playback`, `.playAndRecord`). Passing it with `.record` causes
    ///   AVAudioSession to return kAudioSessionUnsupportedPropertyError
    ///   (OSStatus -50 / errSecParam). The fix is to use only `.allowBluetooth`
    ///   (HFP profile), which is the only Bluetooth mode that carries a mic input.
    ///
    /// AAC codec init fix:
    ///   Mode MUST remain `.default`. `.measurement` mode disables the session's
    ///   built-in sample-rate conversion, so the AAC encoder cannot downconvert
    ///   the 44.1/48 kHz hardware input to the configured 16 kHz — this makes
    ///   `AudioCodecInitialize` fail and `AVAudioRecorder.prepareToRecord()`
    ///   return false. `.default` keeps the full processing chain (including SRC),
    ///   which the AAC encoder requires.
    public func activate() throws {
        do {
            try session.setCategory(
                .record,
                mode: .default,            // required for AAC sample-rate conversion
                options: [.allowBluetooth] // HFP only; A2DP removed (caused -50)
            )
            try session.setActive(true, options: [])
            registerForNotifications()
            EchoLog.audio.debug("AudioSession activated: category=record mode=default options=[allowBluetooth]")
        } catch {
            EchoLog.audio.error("AudioSession activation failed: \(error.localizedDescription, privacy: .public)")
            throw RecordingError.sessionActivationFailed(reason: error.localizedDescription)
        }
    }

    /// Deactivates the session and removes notification observers.
    public func deactivate() {
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
