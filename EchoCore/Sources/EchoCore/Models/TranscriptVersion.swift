//
//  TranscriptVersion.swift
//  EchoCore
//
//  Domain model for a single AI-processed version of a transcript.
//  Mirrors Android's domain.ai.TranscriptVersion data class.
//
//  V2 additions: syncStatus + deleted for Firestore merge support.
//

import Foundation

// MARK: - TranscriptVersion

public struct TranscriptVersion: Identifiable, Equatable, Sendable {
    public let id: String
    public let transcriptId: String
    public let versionType: VersionType
    public let createdAt: Int64          // Unix epoch milliseconds
    public let provider: String
    public let model: String
    public let content: String
    public let metadata: [String: String]

    // ── V2 sync fields ────────────────────────────────────────────────────────
    /// Cloud sync status for this version. Defaults to .pending for new versions.
    public var syncStatus: SyncStatus
    /// Soft-delete flag — mirrors Android's deleted field in TranscriptVersionEntity.
    public var deleted: Bool

    public init(
        id: String = UUID().uuidString,
        transcriptId: String,
        versionType: VersionType,
        createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1_000),
        provider: String,
        model: String,
        content: String,
        metadata: [String: String] = [:],
        syncStatus: SyncStatus = .pending,
        deleted: Bool = false
    ) {
        self.id = id
        self.transcriptId = transcriptId
        self.versionType = versionType
        self.createdAt = createdAt
        self.provider = provider
        self.model = model
        self.content = content
        self.metadata = metadata
        self.syncStatus = syncStatus
        self.deleted = deleted
    }

    /// Date object derived from createdAt milliseconds.
    public var date: Date {
        Date(timeIntervalSince1970: TimeInterval(createdAt) / 1_000)
    }
}
