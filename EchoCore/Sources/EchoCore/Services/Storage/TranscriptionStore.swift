//
//  TranscriptionStore.swift
//  EchoCore
//
//  Thin ModelContext wrapper over TranscriptionModel and TranscriptVersionModel.
//
//  iOS 17 note: #Predicate { $0.id == localVar } causes an EXC_BREAKPOINT
//  inside SwiftData's predicate compiler when used with a String column —
//  a known iOS 17 SwiftData regression. All fetch-by-id operations use a
//  full fetch plus in-memory filter instead.
//

import Foundation
import SwiftData

// MARK: - Testability protocol

@MainActor
public protocol TranscriptionStoreProtocol: AnyObject {
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
    /// Returns all versions whose syncStatus is PENDING — used by SyncService.
    func fetchPendingVersionSync() throws -> [TranscriptVersion]
    /// Updates the syncStatus of a single version row.
    func setVersionSyncStatus(id: String, status: SyncStatus) throws
}

// MARK: - TranscriptionStore

@MainActor
public final class TranscriptionStore: TranscriptionStoreProtocol {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // ══════════════════════════════════════════════════════════════════════════
    // MARK: Transcription CRUD
    // ══════════════════════════════════════════════════════════════════════════

    public func insert(_ transcription: Transcription) throws {
        guard try fetchModel(id: transcription.id) == nil else { return }
        modelContext.insert(TranscriptionModel(transcription))
        try modelContext.save()
    }

    public func update(_ transcription: Transcription) throws {
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

    public func delete(id: String) throws {
        guard let model = try fetchModel(id: id) else { return }
        modelContext.delete(model)
        try modelContext.save()
    }

    public func deleteAll() throws {
        let models = try modelContext.fetch(FetchDescriptor<TranscriptionModel>())
        models.forEach(modelContext.delete)
        let versions = try modelContext.fetch(FetchDescriptor<TranscriptVersionModel>())
        versions.forEach(modelContext.delete)
        try modelContext.save()
    }

    /// Fetches newest-first; pinned items sort before unpinned.
    public func fetch(limit: Int = 100) throws -> [Transcription] {
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

    public func fetch(id: String) throws -> Transcription? {
        try fetchModel(id: id)?.domainValue
    }

    // ══════════════════════════════════════════════════════════════════════════
    // MARK: Favourite / Pin
    // ══════════════════════════════════════════════════════════════════════════

    public func setFavorite(id: String, value: Bool) throws {
        guard let model = try fetchModel(id: id) else { return }
        model.isFavorite = value
        try modelContext.save()
    }

    public func setPin(id: String, value: Bool) throws {
        guard let model = try fetchModel(id: id) else { return }
        model.isPinned = value
        try modelContext.save()
    }

    // ══════════════════════════════════════════════════════════════════════════
    // MARK: Sync status
    // ══════════════════════════════════════════════════════════════════════════

    public func setSyncStatus(id: String, status: SyncStatus) throws {
        guard let model = try fetchModel(id: id) else { return }
        model.syncStatus = status.rawValue
        model.synced = (status == .synced)
        try modelContext.save()
    }

    public func fetchPendingSync() throws -> [Transcription] {
        let all = try modelContext.fetch(FetchDescriptor<TranscriptionModel>())
        return all
            .filter { $0.syncStatus == SyncStatus.pending.rawValue }
            .map(\.domainValue)
    }

    // ══════════════════════════════════════════════════════════════════════════
    // MARK: Version CRUD
    // ══════════════════════════════════════════════════════════════════════════

    public func insertVersion(_ version: TranscriptVersion) throws {
        let all = try modelContext.fetch(FetchDescriptor<TranscriptVersionModel>())
        guard !all.contains(where: { $0.id == version.id }) else { return }
        modelContext.insert(TranscriptVersionModel(version))
        try modelContext.save()
    }

    public func fetchVersions(forTranscriptId id: String) throws -> [TranscriptVersion] {
        let all = try modelContext.fetch(FetchDescriptor<TranscriptVersionModel>())
        return all
            .filter { $0.transcriptId == id && !$0.deleted }
            .sorted { $0.createdAt < $1.createdAt }
            .map(\.domainValue)
    }

    public func deleteVersions(forTranscriptId id: String) throws {
        let all = try modelContext.fetch(FetchDescriptor<TranscriptVersionModel>())
        let affected = all.filter { $0.transcriptId == id }
        affected.forEach(modelContext.delete)
        try modelContext.save()
    }

    public func fetchPendingVersionSync() throws -> [TranscriptVersion] {
        let all = try modelContext.fetch(FetchDescriptor<TranscriptVersionModel>())
        return all
            .filter { $0.syncStatus == SyncStatus.pending.rawValue && !$0.deleted }
            .map(\.domainValue)
    }

    public func setVersionSyncStatus(id: String, status: SyncStatus) throws {
        let all = try modelContext.fetch(FetchDescriptor<TranscriptVersionModel>())
        guard let model = all.first(where: { $0.id == id }) else { return }
        model.syncStatus = status.rawValue
        try modelContext.save()
    }

    // ══════════════════════════════════════════════════════════════════════════
    // MARK: Container factory
    // ══════════════════════════════════════════════════════════════════════════

    public static func makeModelContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(
            for: TranscriptionModel.self, TranscriptVersionModel.self,
            configurations: configuration
        )
    }

    // ══════════════════════════════════════════════════════════════════════════
    // MARK: Private helpers
    // ══════════════════════════════════════════════════════════════════════════

    private func fetchModel(id: String) throws -> TranscriptionModel? {
        let all = try modelContext.fetch(FetchDescriptor<TranscriptionModel>())
        return all.first { $0.id == id }
    }
}
