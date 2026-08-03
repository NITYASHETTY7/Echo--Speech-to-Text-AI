//
//  TranscriptionCoordinator.swift
//  Echo
//
//  Coordinates the full record → transcribe → store workflow.
//
//  Responsibilities:
//    • Accepts a completed RecordingResult from AudioRecorder.
//    • Builds a TranscriptionRequest from Preferences / ProviderSettings.
//    • Runs the TranscriptionPipeline.
//    • Persists the result via TranscriptionStore.
//    • Exposes cancellation and observable state for the UI (Phase 7).
//
//  @MainActor throughout: all dependencies (ProviderFactory, ProviderSettings,
//  Preferences, TranscriptionStore) are MainActor-isolated.
//

import Foundation
import os

// MARK: - Coordinator state

enum CoordinatorState: Equatable, Sendable {
    case idle
    case transcribing(progress: TranscriptionProgress)
    case completed(TranscriptionResponse)
    case failed(TranscriptionError)
    case cancelled
}

// MARK: - TranscriptionCoordinator

@MainActor
final class TranscriptionCoordinator {

    // MARK: - Published state

    private(set) var state: CoordinatorState = .idle {
        didSet { onStateChange?(state) }
    }

    /// Optional callback for state changes (consumed by the ViewModel in Phase 7).
    var onStateChange: ((CoordinatorState) -> Void)?

    // MARK: - Dependencies

    private let pipeline: any TranscriptionPipelineProtocol
    private let preferences: Preferences
    private let providerSettings: ProviderSettings
    private let store: TranscriptionStore?   // nil in unit tests that skip persistence
    /// Returns the UID to stamp on saved transcriptions. "local" for guests.
    private let ownerUidProvider: () -> String

    // MARK: - Cancellation

    private var activeTask: Task<Void, Never>?

    // MARK: - Init

    init(
        pipeline: any TranscriptionPipelineProtocol,
        preferences: Preferences,
        providerSettings: ProviderSettings,
        store: TranscriptionStore? = nil,
        ownerUidProvider: @escaping () -> String = { "local" }
    ) {
        self.pipeline = pipeline
        self.preferences = preferences
        self.providerSettings = providerSettings
        self.store = store
        self.ownerUidProvider = ownerUidProvider
    }

    // MARK: - Public API

    /// Starts a transcription job for `recording`.
    /// If a job is already running it is cancelled before the new one begins.
    func transcribe(recording: RecordingResult) {
        cancelCurrentTask()

        activeTask = Task { [weak self] in
            guard let self else { return }
            await self.run(recording: recording)
        }
    }

    /// Cancels any in-progress transcription.
    func cancel() {
        cancelCurrentTask()
        state = .cancelled
    }

    // MARK: - Private

    private func run(recording: RecordingResult) async {
        let request = TranscriptionRequest(
            recording: recording,
            language: nilIfEmpty(preferences.language),
            model: providerSettings.selectedModel
        )

        do {
            let response = try await pipeline.transcribe(
                request: request,
                onProgress: { [weak self] progress in
                    // pipeline.transcribe is @MainActor, so onProgress is
                    // always called on the main actor — mutate state directly.
                    self?.state = .transcribing(progress: progress)
                }
            )

            guard !Task.isCancelled else {
                state = .cancelled
                return
            }

            // Persist if a store is wired in.
            if let store {
                try? persist(response: response, request: request, store: store)
            }

            state = .completed(response)

        } catch let error as TranscriptionError {
            state = .failed(error)
        } catch is CancellationError {
            state = .cancelled
        } catch {
            state = .failed(.providerFailed(reason: error.localizedDescription))
        }
    }

    private func persist(
        response: TranscriptionResponse,
        request: TranscriptionRequest,
        store: TranscriptionStore
    ) throws {
        let ownerUid = ownerUidProvider()
        let transcription = Transcription(
            id: UUID().uuidString,
            text: response.text,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            model: response.model,
            audioPath: request.recording.fileURL.path,
            userId: ownerUid,
            synced: false,
            duration: response.recordingDuration,
            isFavorite: false,
            isPinned: false,
            syncStatus: ownerUid == "local" ? .localOnly : .pending
        )
        try store.insert(transcription)
    }

    private func cancelCurrentTask() {
        activeTask?.cancel()
        activeTask = nil
    }

    private func nilIfEmpty(_ s: String) -> String? {
        s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : s
    }
}
