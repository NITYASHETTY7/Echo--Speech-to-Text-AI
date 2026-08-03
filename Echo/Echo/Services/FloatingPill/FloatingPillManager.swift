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

    /// Builds a fresh RecordingViewModel from the supplied dependencies and starts recording.
    /// No-op if a session is already active.
    func startRecording(
        store: any TranscriptionStoreProtocol,
        keychainStore: KeychainStore,
        providerSettings: ProviderSettings,
        preferences: Preferences,
        aiService: AIService?,
        ownerUid: String
    ) {
        guard recordingViewModel == nil else { return }

        let recorder = AudioRecorder()
        let factory  = ProviderFactory(keychainStore: keychainStore, providerSettings: providerSettings)
        let pipeline = DefaultTranscriptionPipeline(providerFactory: factory)
        // TranscriptionCoordinator accepts 'any TranscriptionStoreProtocol' via its
        // store parameter typed as TranscriptionStore?; pass nil and let the
        // coordinator work without in-coordinator persistence — the pipeline writes
        // via the coordinator's own store reference set below.
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

        Task { await rvm.startRecording() }
        logger.debug("FloatingPillManager: recording session started")
    }

    /// Stops the active recording and hands off to the transcription pipeline.
    func stopRecording() async {
        guard let rvm = recordingViewModel else { return }
        await rvm.stopRecording()
    }

    /// Cancels the active recording and discards the file.
    func cancelRecording() {
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
        recordingViewModel = nil
        logger.debug("FloatingPillManager: session finished")
    }
}
