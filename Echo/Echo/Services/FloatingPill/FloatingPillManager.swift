//
//  FloatingPillManager.swift
//  Echo
//
//  Central coordinator for the floating pill overlay.
//
//  Responsibilities:
//  • Owns the RecordingViewModel lifecycle (one session at a time).
//  • Observes KeyboardObserver to drive pill opacity and injection availability.
//  • Delegates text injection to TextInjectionCoordinator after transcription.
//  • Exposes the recording session to FloatingPillView via @Observable state.
//
//  Architecture note:
//  FloatingPillManager is a ViewModel — it is created once and injected into
//  HomeView as a @State, then passed into FloatingPillView as a reference.
//  No singleton is used; the dependency graph flows top-down.
//

import Foundation
import SwiftUI
import EchoCore
import os

// MARK: - FloatingPillManager

@MainActor
@Observable
final class FloatingPillManager {

    // MARK: - Dependencies (injected)

    let keyboardObserver: KeyboardObserver
    let textInjector: any TextInjecting

    // MARK: - Observable state

    /// Current recording session, if one is active.
    private(set) var recordingViewModel: RecordingViewModel?

    /// Set to true when stopRecording() is called before (or during) the start
    /// sequence.  Checked inside startAndMaybeStop() after recording begins —
    /// if true, the recording is stopped immediately.
    private var pendingStop: Bool = false

    /// True while recording OR while the keyboard is visible — pill is fully opaque.
    /// False (idle) → pill fades to `idleOpacity`.
    var isActive: Bool {
        recordingViewModel != nil || keyboardObserver.isVisible
    }

    /// Opacity applied by FloatingPillView when `isActive == false`.
    static let idleOpacity: Double = 0.35

    // MARK: - Private

    private let logger = Logger(subsystem: "com.echo.app", category: "FloatingPillManager")

    // MARK: - Init

    init(
        keyboardObserver: KeyboardObserver? = nil,
        textInjector: (any TextInjecting)? = nil
    ) {
        // Both KeyboardObserver and TextInjectionCoordinator are @MainActor —
        // they must be initialised on the main actor.  Since this init is itself
        // called on the main actor (FloatingPillManager is @MainActor), we can
        // use nil-coalescing with lazily-constructed defaults here.
        self.keyboardObserver = keyboardObserver ?? KeyboardObserver()
        self.textInjector     = textInjector     ?? TextInjectionCoordinator()
    }

    // MARK: - Recording session

    /// Builds a fresh RecordingViewModel, starts recording, then — if
    /// stopRecording() was already called (quick hold-and-release) — stops
    /// immediately.  Everything runs in a single serial Task so there is no
    /// window where a stop can be lost.
    func startRecording(
        store: any TranscriptionStoreProtocol,
        keychainStore: KeychainStore,
        providerSettings: ProviderSettings,
        preferences: Preferences,
        aiService: AIService?,
        ownerUid: String
    ) {
        guard recordingViewModel == nil else { return }

        let recorder    = AudioRecorder()
        let factory     = ProviderFactory(keychainStore: keychainStore, providerSettings: providerSettings)
        let pipeline    = DefaultTranscriptionPipeline(providerFactory: factory)
        let coordinator = TranscriptionCoordinator(
            pipeline: pipeline,
            preferences: preferences,
            providerSettings: providerSettings,
            store: store as? TranscriptionStore,
            ownerUidProvider: { ownerUid },
            aiService: aiService
        )
        let rvm = RecordingViewModel(recorder: recorder, coordinator: coordinator)
        recordingViewModel = rvm
        pendingStop = false

        Task {
            // startRecording() handles permission + session + AVAudioRecorder.record()
            // all in one await — when it returns the recorder is either .recording
            // or .failed.  There is no intermediate state left after this await.
            await rvm.startRecording()

            // If the finger was already lifted while we were starting, stop now.
            if pendingStop {
                pendingStop = false
                if rvm.isRecording {
                    await rvm.stopRecording()
                } else {
                    // startRecording failed (permission denied, etc.) — clean up.
                    finishSession()
                }
            }
        }
        logger.debug("FloatingPillManager: recording session enqueued")
    }

    /// Stops the active recording.  If called before the recorder has reached
    /// `.recording` (quick hold-and-release), sets `pendingStop` so the start
    /// Task stops the recorder as soon as it finishes starting.
    func stopRecording() async {
        guard let rvm = recordingViewModel else { return }
        if rvm.isRecording {
            await rvm.stopRecording()
        } else {
            // Recorder hasn't started yet — mark for deferred stop.
            pendingStop = true
            logger.debug("FloatingPillManager: pendingStop set (recorder not yet recording)")
        }
    }

    /// Cancels the active recording and discards the file.
    func cancelRecording() {
        pendingStop = false
        recordingViewModel?.cancelRecording()
        finishSession()
    }

    /// Called after the transcription completes.
    ///
    /// Behaviour:
    ///  - If `injectionEnabled` is true, calls `textInjector.insertTranscript(_:)`.
    ///    • `.injected`        → text placed in focused field; returns nil (no sheet needed).
    ///    • `.copiedToClipboard` → text is on clipboard; returns transcription so caller
    ///                             can show the detail sheet AND the clipboard toast.
    ///  - If `injectionEnabled` is false, returns the transcription for display.
    ///
    /// - Returns: `(transcription?, InsertionResult?)` where `transcription` is non-nil
    ///   when the caller should open the TranscriptDetailSheet, and `result` is non-nil
    ///   when an insertion was attempted (used to drive the clipboard toast).
    @discardableResult
    func handleTranscriptionComplete(
        _ transcription: Transcription,
        injectionEnabled: Bool
    ) -> (transcription: Transcription?, result: InsertionResult?) {
        finishSession()

        guard injectionEnabled else {
            logger.debug("FloatingPillManager: injection disabled — returning transcript for display")
            return (transcription, nil)
        }

        let result = textInjector.insertTranscript(transcription.text)
        switch result {
        case .injected:
            logger.debug("FloatingPillManager: text injected into focused field")
            return (nil, .injected)           // consumed — no sheet to show
        case .copiedToClipboard:
            logger.debug("FloatingPillManager: copied to clipboard — returning transcript for display")
            return (transcription, .copiedToClipboard)   // show sheet + toast
        }
    }

    /// Tears down the recording session state.
    func finishSession() {
        pendingStop = false
        recordingViewModel = nil
        logger.debug("FloatingPillManager: session finished")
    }
}
