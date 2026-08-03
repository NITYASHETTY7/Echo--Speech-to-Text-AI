//
//  TranscriptVersionModel.swift
//  EchoCore
//
//  SwiftData persistence model for AI-generated transcript versions.
//  Mirrors Android's Room TranscriptVersionEntity.
//

import Foundation
import SwiftData

@Model
public final class TranscriptVersionModel {
    public var id: String
    public var transcriptId: String
    public var versionType: String
    public var createdAt: Int          // milliseconds, Int to avoid iOS 17 Int64 trap
    public var provider: String
    public var model: String
    public var content: String
    /// JSON-encoded [String: String] metadata dictionary.
    public var metadataJson: String
    /// Cloud sync status: "PENDING", "SYNCED", "LOCAL_ONLY", "FAILED".
    public var syncStatus: String
    /// Soft-delete flag for Firestore merge support.
    public var deleted: Bool

    public init(
        id: String = UUID().uuidString,
        transcriptId: String,
        versionType: String,
        createdAt: Int,
        provider: String,
        model: String,
        content: String,
        metadataJson: String = "{}",
        syncStatus: String = "PENDING",
        deleted: Bool = false
    ) {
        self.id = id
        self.transcriptId = transcriptId
        self.versionType = versionType
        self.createdAt = createdAt
        self.provider = provider
        self.model = model
        self.content = content
        self.metadataJson = metadataJson
        self.syncStatus = syncStatus
        self.deleted = deleted
    }

    public convenience init(_ version: TranscriptVersion) {
        let jsonString: String
        if let data = try? JSONEncoder().encode(version.metadata),
           let str = String(data: data, encoding: .utf8) {
            jsonString = str
        } else {
            jsonString = "{}"
        }
        self.init(
            id: version.id,
            transcriptId: version.transcriptId,
            versionType: version.versionType.rawValue,
            createdAt: Int(version.createdAt),
            provider: version.provider,
            model: version.model,
            content: version.content,
            metadataJson: jsonString,
            syncStatus: version.syncStatus.rawValue,
            deleted: version.deleted
        )
    }

    public var domainValue: TranscriptVersion {
        let parsedMetadata: [String: String]
        if let data = metadataJson.data(using: .utf8),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            parsedMetadata = dict
        } else {
            parsedMetadata = [:]
        }
        return TranscriptVersion(
            id: id,
            transcriptId: transcriptId,
            versionType: VersionType(rawValue: versionType) ?? .custom,
            createdAt: Int64(createdAt),
            provider: provider,
            model: model,
            content: content,
            metadata: parsedMetadata,
            syncStatus: SyncStatus(rawValue: syncStatus) ?? .pending,
            deleted: deleted
        )
    }
}
