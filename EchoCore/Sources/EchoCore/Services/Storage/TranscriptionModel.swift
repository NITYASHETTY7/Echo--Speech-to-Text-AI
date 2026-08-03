//
//  TranscriptionModel.swift
//  EchoCore
//
//  SwiftData persistence model.
//  V2 additions: isFavorite, isPinned, syncStatus with backward-compatible defaults.
//  V3 additions: updatedAt (epoch ms, defaults to timestamp), rawTranscript.
//

import Foundation
import SwiftData

@Model
public final class TranscriptionModel {
    public var id: String
    public var text: String
    public var timestamp: Int       // Int64 on every Apple platform; avoids iOS 17 schema trap
    public var model: String
    public var audioPath: String?
    public var userId: String
    public var synced: Bool
    /// Recording duration in seconds. 0.0 means "not recorded" (nil in domain model).
    public var duration: Double

    // ── V2 additions ──────────────────────────────────────────────────────────
    public var isFavorite: Bool
    public var isPinned: Bool
    /// One of "PENDING", "SYNCED", "LOCAL_ONLY", "FAILED".
    public var syncStatus: String

    // ── V3 additions ──────────────────────────────────────────────────────────
    /// Last modification time in epoch milliseconds.
    /// Default of 0 lets SwiftData auto-migrate existing rows without a
    /// manual migration plan — the sort logic treats 0 as "use timestamp instead".
    public var updatedAt: Int = 0

    /// Raw Whisper transcript in the spoken language.
    /// Nil for records created before V3 (callers fall back to text).
    public var rawTranscript: String?

    /// Display-name of the detected spoken language (e.g. "Kannada").
    /// Nil for records created before this field was introduced.
    public var detectedLanguage: String?

    public init(
        id: String,
        text: String,
        timestamp: Int,
        model: String,
        audioPath: String? = nil,
        userId: String,
        synced: Bool = false,
        duration: Double = 0.0,
        isFavorite: Bool = false,
        isPinned: Bool = false,
        syncStatus: String = "PENDING",
        updatedAt: Int? = nil,
        rawTranscript: String? = nil,
        detectedLanguage: String? = nil
    ) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.model = model
        self.audioPath = audioPath
        self.userId = userId
        self.synced = synced
        self.duration = duration
        self.isFavorite = isFavorite
        self.isPinned = isPinned
        self.syncStatus = syncStatus
        self.updatedAt = updatedAt ?? timestamp
        self.rawTranscript = rawTranscript
        self.detectedLanguage = detectedLanguage
    }

    public convenience init(_ transcription: Transcription) {
        self.init(
            id: transcription.id,
            text: transcription.text,
            timestamp: Int(transcription.timestamp),
            model: transcription.model,
            audioPath: transcription.audioPath,
            userId: transcription.userId,
            synced: transcription.synced,
            duration: transcription.duration ?? 0.0,
            isFavorite: transcription.isFavorite,
            isPinned: transcription.isPinned,
            syncStatus: transcription.syncStatus.rawValue,
            updatedAt: Int(transcription.updatedAt),
            rawTranscript: transcription.rawTranscript,
            detectedLanguage: transcription.detectedLanguage
        )
    }

    public var domainValue: Transcription {
        Transcription(
            id: id,
            text: text,
            timestamp: Int64(timestamp),
            model: model,
            audioPath: audioPath,
            userId: userId,
            synced: synced,
            duration: duration > 0 ? duration : nil,
            isFavorite: isFavorite,
            isPinned: isPinned,
            syncStatus: SyncStatus(rawValue: syncStatus) ?? .pending,
            updatedAt: Int64(updatedAt),
            rawTranscript: rawTranscript,
            detectedLanguage: detectedLanguage
        )
    }
}
