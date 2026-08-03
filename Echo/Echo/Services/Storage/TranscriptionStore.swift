//
//  TranscriptionStore.swift
//  Echo
//
//  Thin ModelContext wrapper over both TranscriptionModel and TranscriptVersionModel.
//
//  iOS 17 note: #Predicate { $0.id == localVar } causes an EXC_BREAKPOINT
//  inside SwiftData's predicate compiler when used with a String column —
//  a known iOS 17 SwiftData regression. All fetch-by-id operations use a
//  full fetch plus in-memory filter instead, which is safe and correct for
//  the small dataset Echo manages.
//

import Foundation
import SwiftData

// MARK: - Testability protocol

/// Protocol allowing ViewModels to depend on an abstract store rather than
/// the concrete SwiftData implementation.
@MainActor
protocol TranscriptionStoreProtocol: AnyObject {
    // ── Transcription CRUD ────────────────────────────────────────────────────
    func insert(_ transcription: Transcription) throws
    func update(_ transcription: Transcription) throws
    func delete(id: String) throws
    func deleteAll() throws
    func fetch(limit: Int) throws -> [Transcription]
    func fetch(id: String) throws -> Transcription?

    // ── Favourite / Pin toggles ───────────────────────────────────────────────
    func setFavorite(id: String, value: Bool) throws
    func setPin(id: String, value: Bool) throws

    // ── Sync status ───────────────────────────────────────────────────────────
    func setSyncStatus(id: String, status: SyncStatus) throws
    func fetchPendingSync() throws -> [Transcription]

    // ── Version CRUD ──────────────────────────────────────────────────────────
    func insertVersion(_ version: TranscriptVersion) throws
    func fetchVersions(forTranscriptId id: String) throws -> [TranscriptVersion]
    func deleteVersions(forTranscriptId id: String) throws
    func fetchPendingVersionSync() throws -> [TranscriptVersion]
    func setVersionSyncStatus(id: String, status: SyncStatus) throws
}

// MARK: - TranscriptionStore

@MainActor
final class TranscriptionStore: TranscriptionStoreProtocol {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // ══════════════════════════════════════════════════════════════════════════
    // MARK: Transcription CRUD
    // ══════════════════════════════════════════════════════════════════════════

    /// Inserts a transcription and saves immediately.
    /// Existing IDs are ignored, matching Room's OnConflictStrategy.IGNORE.
    func insert(_ transcription: Transcription) throws {
        guard try fetchModel(id: transcription.id) == nil else { return }
        modelContext.insert(TranscriptionModel(transcription))
        try modelContext.save()
    }

    /// Full update — replaces all mutable fields.
    func update(_ transcription: Transcription) throws {
        guard let model = try fetchModel(id: transcription.id) else { return }
        model.text = transcription.text
        model.timestamp = Int(transcription.timestamp)
        model.model = transcription.model
        model.audioPath = transcription.audioPath
        model.userId = transcription.userId
        model.synced = transcription.synced
        model.duration = transcription.duration ?? 0.0
        model.isFavorite = transcription.isFavorite
        model.isPinned = transcription.isPinned
        model.syncStatus = transcription.syncStatus.rawValue
        model.updatedAt = Int(transcription.updatedAt)
        // rawTranscript and detectedLanguage are write-once: only set if not already stored.
        if model.rawTranscript == nil, let raw = transcription.rawTranscript {
            model.rawTranscript = raw
        }
        if model.detectedLanguage == nil, let lang = transcription.detectedLanguage {
            model.detectedLanguage = lang
        }
        try modelContext.save()
    }

    /// Deletes the row with the supplied ID, if present.
    func delete(id: String) throws {
        guard let model = try fetchModel(id: id) else { return }
        modelContext.delete(model)
        try modelContext.save()
    }

    /// Deletes all saved transcriptions (and their versions).
    func deleteAll() throws {
        let models = try modelContext.fetch(FetchDescriptor<TranscriptionModel>())
        models.forEach(modelContext.delete)
        let versions = try modelContext.fetch(FetchDescriptor<TranscriptVersionModel>())
        versions.forEach(modelContext.delete)
        try modelContext.save()
    }

    /// Fetches the newest transcriptions first.
    /// Pinned items sort before unpinned; within each group newest-first.
    func fetch(limit: Int = 100) throws -> [Transcription] {
        guard limit > 0 else { return [] }
        let all = try modelContext.fetch(FetchDescriptor<TranscriptionModel>())
        return all
            .sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned }
                // Sort by the later of updatedAt and timestamp so records
                // modified after creation (e.g. via sync) bubble to the top.
                let lhs = max($0.updatedAt, $0.timestamp)
                let rhs = max($1.updatedAt, $1.timestamp)
                return lhs > rhs
            }
            .prefix(limit)
            .map(\.domainValue)
    }

    /// Fetches one transcription by its stable ID.
    func fetch(id: String) throws -> Transcription? {
        try fetchModel(id: id)?.domainValue
    }

    // ══════════════════════════════════════════════════════════════════════════
    // MARK: Favourite / Pin
    // ══════════════════════════════════════════════════════════════════════════

    func setFavorite(id: String, value: Bool) throws {
        guard let model = try fetchModel(id: id) else { return }
        model.isFavorite = value
        try modelContext.save()
    }

    func setPin(id: String, value: Bool) throws {
        guard let model = try fetchModel(id: id) else { return }
        model.isPinned = value
        try modelContext.save()
    }

    // ══════════════════════════════════════════════════════════════════════════
    // MARK: Sync status
    // ══════════════════════════════════════════════════════════════════════════

    func setSyncStatus(id: String, status: SyncStatus) throws {
        guard let model = try fetchModel(id: id) else { return }
        model.syncStatus = status.rawValue
        model.synced = (status == .synced)
        try modelContext.save()
    }

    /// Returns all transcriptions whose syncStatus is PENDING.
    /// Used by SyncService to decide what needs uploading.
    func fetchPendingSync() throws -> [Transcription] {
        let all = try modelContext.fetch(FetchDescriptor<TranscriptionModel>())
        return all
            .filter { $0.syncStatus == SyncStatus.pending.rawValue }
            .map(\.domainValue)
    }

    // ══════════════════════════════════════════════════════════════════════════
    // MARK: Version CRUD
    // ══════════════════════════════════════════════════════════════════════════

    /// Persists a new TranscriptVersion; ignores duplicates.
    func insertVersion(_ version: TranscriptVersion) throws {
        let all = try modelContext.fetch(FetchDescriptor<TranscriptVersionModel>())
        guard !all.contains(where: { $0.id == version.id }) else { return }
        modelContext.insert(TranscriptVersionModel(version))
        try modelContext.save()
    }

    /// Returns all versions for the given transcript, ordered oldest-first.
    func fetchVersions(forTranscriptId id: String) throws -> [TranscriptVersion] {
        let all = try modelContext.fetch(FetchDescriptor<TranscriptVersionModel>())
        return all
            .filter { $0.transcriptId == id && !$0.deleted }
            .sorted { $0.createdAt < $1.createdAt }
            .map(\.domainValue)
    }

    /// Soft-deletes all version rows linked to a transcript.
    /// Hard deletion is handled by deleteAll().
    func deleteVersions(forTranscriptId id: String) throws {
        let all = try modelContext.fetch(FetchDescriptor<TranscriptVersionModel>())
        let affected = all.filter { $0.transcriptId == id }
        affected.forEach(modelContext.delete)
        try modelContext.save()
    }

    func fetchPendingVersionSync() throws -> [TranscriptVersion] {
        let all = try modelContext.fetch(FetchDescriptor<TranscriptVersionModel>())
        return all
            .filter { $0.syncStatus == SyncStatus.pending.rawValue && !$0.deleted }
            .map(\.domainValue)
    }

    func setVersionSyncStatus(id: String, status: SyncStatus) throws {
        let all = try modelContext.fetch(FetchDescriptor<TranscriptVersionModel>())
        guard let model = all.first(where: { $0.id == id }) else { return }
        model.syncStatus = status.rawValue
        try modelContext.save()
    }

    // ══════════════════════════════════════════════════════════════════════════
    // MARK: Container factory
    // ══════════════════════════════════════════════════════════════════════════

    /// Provides a production or in-memory container for the app and tests.
    static func makeModelContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(
            for: TranscriptionModel.self, TranscriptVersionModel.self,
            configurations: configuration
        )
    }

    // ══════════════════════════════════════════════════════════════════════════
    // MARK: Private helpers
    // ══════════════════════════════════════════════════════════════════════════

    /// Fetches a TranscriptionModel by ID using a full-table fetch + in-memory filter.
    /// Avoids the iOS 17 SwiftData #Predicate EXC_BREAKPOINT on String columns.
    private func fetchModel(id: String) throws -> TranscriptionModel? {
        let all = try modelContext.fetch(FetchDescriptor<TranscriptionModel>())
        return all.first { $0.id == id }
    }
}
