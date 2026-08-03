//
//  TranscriptVersion.swift
//  Echo
//
//  Domain model for a single AI-processed version of a transcript.
//  V2 additions: syncStatus + deleted for Firestore merge support.
//  Mirrors EchoCore/Models/TranscriptVersion.swift (excluded from app target via membershipExceptions).
//

import Foundation

struct TranscriptVersion: Identifiable, Equatable, Sendable {
    let id: String
    let transcriptId: String
    let versionType: VersionType
    let createdAt: Int64
    let provider: String
    let model: String
    let content: String
    let metadata: [String: String]
    var syncStatus: SyncStatus
    var deleted: Bool

    init(
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

    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(createdAt) / 1_000)
    }
}
