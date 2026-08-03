//
//  AIViewModel.swift
//  Echo
//
//  Presentation ViewModel for AI rewrite operations.
//  Mirrors Android's AIViewModel exactly.
//
//  Manages:
//    - versions list for a given transcript
//    - active version selection (defaults to latest)
//    - rewrite sheet visibility
//    - custom prompt text
//    - loading / error / success states
//

import Foundation
import EchoCore
import os

// MARK: - AiUiState

/// Mirrors Android's AiUiState data class.
struct AiUiState: Equatable {
    var transcriptId: String = ""
    var versions: [TranscriptVersion] = []
    var activeIndex: Int = 0
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var successMessage: String? = nil
    var isRewriteSheetVisible: Bool = false
    var customPromptText: String = ""

    // Computed
    var activeVersion: TranscriptVersion? {
        guard !versions.isEmpty, activeIndex < versions.count else { return nil }
        return versions[activeIndex]
    }
    var hasVersions: Bool { !versions.isEmpty }
    var isCustomPromptValid: Bool {
        !customPromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && customPromptText.count <= 500
    }
}

// MARK: - AIViewModel

@MainActor
@Observable
final class AIViewModel {

    // MARK: - Public state

    private(set) var state = AiUiState()

    // MARK: - Dependencies

    private let aiService: AIService
    private let store: any TranscriptionStoreProtocol
    private let logger = Logger(subsystem: "com.echo.app", category: "AIViewModel")

    // MARK: - Init

    init(aiService: AIService, store: any TranscriptionStoreProtocol) {
        self.aiService = aiService
        self.store = store
    }

    // MARK: - Load

    func loadTranscript(transcriptId: String, rawText: String) {
        state.transcriptId = transcriptId
        let stored = (try? store.fetchVersions(forTranscriptId: transcriptId)) ?? []
        let originalID = "\(transcriptId)-original"
        // Synthetic Original with a real timestamp (now), not epoch 0.
        // provider/model left blank because AIViewModel doesn't have access
        // to the parent Transcription's metadata — matches Android behaviour
        // where Original version comes from the recording pipeline.
        let original = TranscriptVersion(
            id: originalID,
            transcriptId: transcriptId,
            versionType: .original,
            createdAt: Int64(Date().timeIntervalSince1970 * 1_000),
            provider: "",
            model: "",
            content: rawText
        )
        // Dedup: filter out any stored version that claims to be the original
        let filtered = stored.filter { $0.id != originalID && $0.versionType != .original }
        let all = [original] + filtered
        state.versions = all
        // Default to latest (mirrors Android: activeIndex = MAX clamped to lastIndex)
        state.activeIndex = max(0, all.count - 1)
    }

    // MARK: - Version selection

    func selectVersion(index: Int) {
        guard index >= 0, index < state.versions.count else { return }
        state.activeIndex = index
    }

    // MARK: - Rewrite sheet

    func showRewriteSheet() { state.isRewriteSheetVisible = true }
    func hideRewriteSheet() { state.isRewriteSheetVisible = false }

    func onCustomPromptChanged(_ text: String) {
        state.customPromptText = String(text.prefix(500))
    }

    // MARK: - Apply operations

    func applyPreset(templateId: String) {
        guard !state.transcriptId.isEmpty else { return }
        let sourceText = state.activeVersion?.content ?? ""
        runAI {
            try await self.unwrap(
                await self.aiService.applyPreset(
                    transcriptId: self.state.transcriptId,
                    sourceText: sourceText,
                    templateId: templateId
                )
            )
        }
    }

    func applyTranslation(targetLanguage: String) {
        guard !state.transcriptId.isEmpty else { return }
        let sourceText = state.activeVersion?.content ?? ""
        runAI {
            try await self.unwrap(
                await self.aiService.applyTranslation(
                    transcriptId: self.state.transcriptId,
                    sourceText: sourceText,
                    targetLanguage: targetLanguage
                )
            )
        }
    }

    func applyCustomPrompt() {
        guard state.isCustomPromptValid, !state.transcriptId.isEmpty else { return }
        let instruction = state.customPromptText.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceText = state.activeVersion?.content ?? ""
        runAI {
            try await self.unwrap(
                await self.aiService.applyCustomRewrite(
                    transcriptId: self.state.transcriptId,
                    sourceText: sourceText,
                    instruction: instruction
                )
            )
        }
    }

    // MARK: - State helpers

    func dismissError()   { state.errorMessage = nil }
    func dismissSuccess() { state.successMessage = nil }

    func getPromptTemplates() -> [PromptTemplate] {
        aiService.getAllTemplates()
            .sorted { $0.title < $1.title }
    }

    // MARK: - Private

    private func runAI(_ operation: @escaping () async throws -> TranscriptVersion) {
        state.isLoading = true
        state.errorMessage = nil
        state.isRewriteSheetVisible = false

        Task {
            do {
                let version = try await operation()
                // Append to versions list and select it
                state.versions.append(version)
                state.activeIndex = state.versions.count - 1
                state.successMessage = "\(version.versionType.displayName) created."
                logger.debug("AI operation succeeded: \(version.versionType.displayName, privacy: .public)")
            } catch {
                state.errorMessage = error.localizedDescription
                logger.error("AI operation failed: \(error.localizedDescription, privacy: .public)")
            }
            state.isLoading = false
        }
    }

    private func unwrap<T>(_ result: Result<T, Error>) throws -> T {
        switch result {
        case .success(let v): return v
        case .failure(let e): throw e
        }
    }
}
