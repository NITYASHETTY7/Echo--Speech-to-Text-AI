//
//  TranscriptionCoordinator.swift
//  EchoCore
//
//  Coordinates the full record → transcribe → AI pipeline → store workflow.
//
//  V3: optional AIService injected at init time. After a successful transcription,
//  runs the post-transcription pipeline (grammar + auto-enhance) if configured.
//
//  ownerUidProvider is a closure so EchoCore never depends on Firebase.
//

import Foundation
import os

// MARK: - Coordinator state

public enum CoordinatorState: Equatable, Sendable {
    case idle
    case transcribing(progress: TranscriptionProgress)
    /// AI post-processing is running after transcription.
    case processing
    case completed(TranscriptionResponse)
    case failed(TranscriptionError)
    case cancelled

    public static func == (lhs: CoordinatorState, rhs: CoordinatorState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.processing, .processing), (.cancelled, .cancelled): return true
        case (.transcribing(let a), .transcribing(let b)): return a == b
        case (.completed(let a), .completed(let b)): return a == b
        case (.failed(let a), .failed(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - TranscriptionCoordinator

@MainActor
public final class TranscriptionCoordinator {

    // MARK: - Published state

    public private(set) var state: CoordinatorState = .idle {
        didSet { onStateChange?(state) }
    }

    public var onStateChange: ((CoordinatorState) -> Void)?

    // MARK: - Dependencies

    private let pipeline: any TranscriptionPipelineProtocol
    private let preferences: Preferences
    private let providerSettings: ProviderSettings
    private let store: TranscriptionStore?
    private let ownerUidProvider: () -> String
    /// Optional AI post-processing service. Nil = no AI pipeline.
    private let aiService: AIService?

    // MARK: - Cancellation

    private var activeTask: Task<Void, Never>?

    // MARK: - Init

    public init(
        pipeline: any TranscriptionPipelineProtocol,
        preferences: Preferences,
        providerSettings: ProviderSettings,
        store: TranscriptionStore? = nil,
        ownerUidProvider: @escaping () -> String = { "local" },
        aiService: AIService? = nil
    ) {
        self.pipeline = pipeline
        self.preferences = preferences
        self.providerSettings = providerSettings
        self.store = store
        self.ownerUidProvider = ownerUidProvider
        self.aiService = aiService
    }

    // MARK: - Public API

    public func transcribe(recording: RecordingResult) {
        cancelCurrentTask()
        activeTask = Task { [weak self] in
            guard let self else { return }
            await self.run(recording: recording)
        }
    }

    public func cancel() {
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
                    self?.state = .transcribing(progress: progress)
                }
            )

            guard !Task.isCancelled else { state = .cancelled; return }

            // ── Persist raw transcript ────────────────────────────────────────
            var transcriptionId: String? = nil
            if let store {
                transcriptionId = try? persistAndGetId(response: response, request: request, store: store)
            }

            // ── Optional AI post-processing pipeline ─────────────────────────
            if let aiService, let tid = transcriptionId {
                state = .processing
                _ = await aiService.processPostTranscription(
                    transcriptId: tid,
                    rawText: response.text,
                    grammarEnabled: preferences.grammar,
                    autoEnhanceEnabled: preferences.autoEnhance
                )
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

    /// Persists the transcription and returns its stable ID.
    @discardableResult
    private func persistAndGetId(
        response: TranscriptionResponse,
        request: TranscriptionRequest,
        store: TranscriptionStore
    ) throws -> String {
        let ownerUid = ownerUidProvider()
        let id = UUID().uuidString
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let transcription = Transcription(
            id: id,
            text: response.text,
            timestamp: nowMs,
            model: response.model,
            audioPath: request.recording.fileURL.path,
            userId: ownerUid,
            synced: false,
            duration: response.recordingDuration,
            isFavorite: false,
            isPinned: false,
            syncStatus: ownerUid == "local" ? .localOnly : .pending,
            updatedAt: nowMs,
            rawTranscript: response.text,         // preserve raw Whisper text in spoken language
            detectedLanguage: response.detectedLanguage
        )
        try store.insert(transcription)
        return id
    }

    private func cancelCurrentTask() {
        activeTask?.cancel()
        activeTask = nil
    }

    private func nilIfEmpty(_ s: String) -> String? {
        s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : s
    }
}
