//
//  TranscriptViewModel.swift
//  Echo
//
//  ViewModel for a single transcript.
//  V3: AI rewrite integration — requestRewrite(), requestTranslation(),
//      requestCustomRewrite(), isProcessing, processingError.
//  V4: Two-language state —
//      • detectedLanguage: read-only, auto-set at init from transcription.detectedLanguage
//      • selectedOutputLanguage: user-editable, seeded from detectedLanguage on first
//        open, then persisted to Preferences.rewriteOutputLanguage so the user's choice
//        survives sheet dismissal and re-open.
//      These two are kept strictly separate so auto-detection never overwrites a
//      manually chosen language.
//

import Foundation
import EchoCore
import UIKit
import os

@MainActor
@Observable
public final class TranscriptViewModel {

    // MARK: - Display state

    private(set) var text: String
    private(set) var providerName: String
    private(set) var modelName: String
    private(set) var recordingDuration: TimeInterval?
    private(set) var timestamp: Date
    private(set) var didCopy: Bool = false
    private(set) var deleteError: Error?

    // ── Favourite / pin ───────────────────────────────────────────────────────
    private(set) var isFavorite: Bool = false
    private(set) var isPinned: Bool = false

    // ── Version management ────────────────────────────────────────────────────
    private(set) var versions: [TranscriptVersion] = []

    var activeVersionIndex: Int = 0 {
        didSet {
            guard activeVersionIndex < versions.count else { return }
            text = versions[activeVersionIndex].content
        }
    }

    var activeVersion: TranscriptVersion? {
        guard !versions.isEmpty, activeVersionIndex < versions.count else { return nil }
        return versions[activeVersionIndex]
    }

    private let rawText: String

    // ── Language state (V4) ───────────────────────────────────────────────────

    /// The language of the original transcript as detected at recording time.
    /// Read-only — never changed after init.
    private(set) var detectedLanguage: String

    /// The user's currently selected output language for all AI rewrites.
    /// Seeded from detectedLanguage on first open.
    /// Changing this persists to Preferences immediately.
    var selectedOutputLanguage: String {
        didSet {
            preferences?.rewriteOutputLanguage = selectedOutputLanguage
        }
    }

    // ── AI processing state (V3) ──────────────────────────────────────────────
    private(set) var isProcessing: Bool = false
    private(set) var processingError: String? = nil

    // MARK: - Dependencies

    private let transcriptionID: String?
    private let store: (any TranscriptionStoreProtocol)?
    private let aiService: AIService?
    private weak var preferences: Preferences?

    // MARK: - Init (from persisted Transcription)

    init(
        transcription: Transcription,
        store: (any TranscriptionStoreProtocol)? = nil,
        aiService: AIService? = nil,
        preferences: Preferences? = nil
    ) {
        self.rawText = transcription.rawTranscript ?? transcription.text
        self.text = transcription.rawTranscript ?? transcription.text
        self.modelName = transcription.model
        self.timestamp = Date(timeIntervalSince1970: TimeInterval(transcription.timestamp) / 1_000)
        self.transcriptionID = transcription.id
        self.store = store
        self.aiService = aiService
        self.preferences = preferences

        self.isFavorite = transcription.isFavorite
        self.isPinned = transcription.isPinned

        let resolvedName = ProviderRegistry.allConfigs
            .first { $0.supportedModels.contains(transcription.model) }?.displayName
        self.providerName = resolvedName ?? transcription.model
        self.recordingDuration = nil

        // Language state: detected is fixed at the recorded language.
        // selectedOutput is seeded from detected so AI rewrites default to the
        // spoken language. The user can change it in the sheet; that change is
        // written to Preferences via didSet and will persist for the *next*
        // transcript opened — but we never let the global Preferences key
        // override the per-transcript detected language here.
        let detected = transcription.detectedLanguage ?? "English"
        self.detectedLanguage = detected
        self.selectedOutputLanguage = detected

        loadVersionsFromStore(transcription: transcription)
    }

    // MARK: - Init (from transient TranscriptionResponse)

    init(
        response: TranscriptionResponse,
        store: (any TranscriptionStoreProtocol)? = nil,
        aiService: AIService? = nil,
        preferences: Preferences? = nil
    ) {
        self.rawText = response.text
        self.text = response.text
        self.providerName = response.providerId.displayName
        self.modelName = response.model
        self.recordingDuration = response.recordingDuration
        self.timestamp = Date()
        self.transcriptionID = nil
        self.store = store
        self.aiService = aiService
        self.preferences = preferences

        let detected = response.detectedLanguage
        self.detectedLanguage = detected
        // Seed from the detected spoken language — same rule as the persisted init.
        self.selectedOutputLanguage = detected
    }

    // MARK: - Version loading

    private func loadVersionsFromStore(transcription: Transcription) {
        guard let store else { return }
        let loaded = (try? store.fetchVersions(forTranscriptId: transcription.id)) ?? []
        let resolvedName = ProviderRegistry.allConfigs
            .first { $0.supportedModels.contains(transcription.model) }?.displayName
        // Synthetic Original — never persisted to the store (always regenerated here).
        // ID is stable: "{transcriptId}-original" — dedup guard below relies on this.
        // Always uses rawTranscript (spoken language) — fall back to text for older records.
        let originalID = "\(transcription.id)-original"
        let originalContent = transcription.rawTranscript ?? transcription.text
        let original = TranscriptVersion(
            id: originalID,
            transcriptId: transcription.id,
            versionType: .original,
            createdAt: transcription.timestamp,
            provider: resolvedName ?? transcription.model,
            model: transcription.model,
            content: originalContent
        )
        // Guard: never include a stored version with the synthetic original's ID.
        // This prevents double-Original if a bug ever persisted the synthetic version.
        let filteredLoaded = loaded.filter { $0.id != originalID && $0.versionType != .original }
        versions = [original] + filteredLoaded
        // Default to latest version (mirrors Android: activeIndex = MAX_VALUE clamped)
        activeVersionIndex = max(0, versions.count - 1)
        text = versions[activeVersionIndex].content
    }

    /// Reloads versions from store — called after AI processing completes.
    /// Preserves exactly one synthetic Original at index 0.
    func loadVersions() {
        guard let id = transcriptionID, let store else { return }
        let loaded = (try? store.fetchVersions(forTranscriptId: id)) ?? []
        // Always reuse the existing in-memory Original so its metadata stays accurate.
        // If versions is somehow empty, synthesize from rawText.
        let existingOriginal = versions.first { $0.versionType == .original }
        let originalID = "\(id)-original"
        let original = existingOriginal ?? TranscriptVersion(
            id: originalID,
            transcriptId: id,
            versionType: .original,
            createdAt: Int64(timestamp.timeIntervalSince1970 * 1_000),
            provider: providerName,
            model: modelName,
            content: rawText
        )
        // Filter out any stored version that has the synthetic Original's ID or versionType,
        // so we can never end up with [original, original, v1, v2].
        let filteredLoaded = loaded.filter { $0.id != originalID && $0.versionType != .original }
        versions = [original] + filteredLoaded
        // Jump to latest after adding a new AI version
        activeVersionIndex = max(0, versions.count - 1)
        text = versions[activeVersionIndex].content
    }

    // MARK: - AI Rewrites (V3/V4)

    /// Apply a named preset rewrite (professional, summary, etc.).
    /// Uses the current `selectedOutputLanguage` so the AI always responds in
    /// the user's chosen language, regardless of the input transcript's language.
    func requestRewrite(templateId: String, outputLanguage: String? = nil) {
        guard let id = transcriptionID, let aiService else {
            processingError = "AI service is not available."
            return
        }
        let lang = outputLanguage ?? selectedOutputLanguage
        let sourceText = rawText   // always rewrite from the original spoken-language text
        isProcessing = true
        processingError = nil

        Task {
            let result = await aiService.applyPreset(
                transcriptId: id,
                sourceText: sourceText,
                templateId: templateId,
                outputLanguage: lang
            )
            switch result {
            case .success(let version): appendVersion(version)
            case .failure(let error):   processingError = error.localizedDescription
            }
            isProcessing = false
        }
    }

    /// Apply a custom rewrite instruction.
    /// `outputLanguage` is forwarded directly to AIService — the instruction
    /// text must NOT contain language directives (the prompt builder handles it).
    func requestCustomRewrite(instruction: String, outputLanguage: String? = nil) {
        guard let id = transcriptionID, let aiService else {
            processingError = "AI service is not available."
            return
        }
        let lang = outputLanguage ?? selectedOutputLanguage
        let sourceText = rawText
        isProcessing = true
        processingError = nil

        Task {
            let result = await aiService.applyCustomRewrite(
                transcriptId: id,
                sourceText: sourceText,
                instruction: instruction.trimmingCharacters(in: .whitespacesAndNewlines),
                outputLanguage: lang
            )
            switch result {
            case .success(let version): appendVersion(version)
            case .failure(let error):   processingError = error.localizedDescription
            }
            isProcessing = false
        }
    }

    /// Translate into `targetLanguage`.
    /// When called from the Translate preset the target language IS the output language.
    func requestTranslation(targetLanguage: String? = nil) {
        guard let id = transcriptionID, let aiService else {
            processingError = "AI service is not available."
            return
        }
        let lang = targetLanguage ?? selectedOutputLanguage
        let sourceText = rawText
        isProcessing = true
        processingError = nil

        Task {
            let result = await aiService.applyTranslation(
                transcriptId: id,
                sourceText: sourceText,
                targetLanguage: lang
            )
            switch result {
            case .success(let version): appendVersion(version)
            case .failure(let error):   processingError = error.localizedDescription
            }
            isProcessing = false
        }
    }

    func dismissProcessingError() {
        processingError = nil
    }

    // MARK: - Core actions

    func copyToClipboard() {
        UIPasteboard.general.string = text
        EchoLog.ui.debug("Copied transcript to clipboard (\(self.text.count) chars)")
        didCopy = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self.didCopy = false
        }
    }

    func delete() {
        guard let id = transcriptionID, let store else { return }
        deleteError = nil
        do {
            try store.deleteVersions(forTranscriptId: id)
            try store.delete(id: id)
        } catch { deleteError = error }
    }

    func clearError() { deleteError = nil }

    func toggleFavorite() {
        guard let id = transcriptionID, let store else { return }
        let newValue = !isFavorite
        do { try store.setFavorite(id: id, value: newValue); isFavorite = newValue }
        catch { deleteError = error }
    }

    func togglePin() {
        guard let id = transcriptionID, let store else { return }
        let newValue = !isPinned
        do { try store.setPin(id: id, value: newValue); isPinned = newValue }
        catch { deleteError = error }
    }

    func appendVersion(_ version: TranscriptVersion) {
        // Persist to store first, then rebuild the full versions list.
        // Using loadVersions() as the single rebuild path guarantees exactly
        // one synthetic Original at index 0 — no raw appending that bypasses dedup.
        if let store {
            do {
                try store.insertVersion(version)
            } catch {
                deleteError = error
                return
            }
        } else {
            // No store (transient response) — simple append is safe
            versions.append(version)
            activeVersionIndex = versions.count - 1
            return
        }
        // Rebuild from store (dedup logic lives in loadVersions)
        loadVersions()
    }

    // MARK: - Formatting

    var relativeTimestamp: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: timestamp, relativeTo: Date())
    }

    var formattedDuration: String? {
        guard let s = recordingDuration else { return nil }
        let total = Int(s); return String(format: "%d:%02d", total / 60, total % 60)
    }
}
