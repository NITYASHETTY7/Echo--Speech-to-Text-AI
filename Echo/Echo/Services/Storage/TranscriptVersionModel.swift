//
//  TranscriptVersionModel.swift
//  Echo
//
//  SwiftData persistence model for AI-generated transcript versions.
//  Mirrors Android's Room TranscriptVersionEntity.
//
//  V2: domainValue now surfaces syncStatus and deleted back to domain layer.
//

import Foundation
import SwiftData

@Model
final class TranscriptVersionModel {
    var id: String
    var transcriptId: String
    var versionType: String
    var createdAt: Int
    var provider: String
    var model: String
    var content: String
    var metadataJson: String
    var syncStatus: String
    var deleted: Bool

    init(
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

    convenience init(_ version: TranscriptVersion) {
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

    var domainValue: TranscriptVersion {
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
