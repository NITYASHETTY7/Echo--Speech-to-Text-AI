//
//  Transcription.swift
//  EchoCore
//
//  Domain representation of a saved transcription.
//  Fields mirror Android's domain.model.Transcription.
//  Added in V2: isFavorite, isPinned, syncStatus
//  Added in V3: updatedAt (epoch ms), rawTranscript, detectedLanguage
//

import Foundation

// MARK: - SyncStatus

/// Mirrors Android's "PENDING" / "SYNCED" / "LOCAL_ONLY" string constants.
public enum SyncStatus: String, Codable, Sendable {
    case pending   = "PENDING"
    case synced    = "SYNCED"
    case localOnly = "LOCAL_ONLY"
    case failed    = "FAILED"
}

// MARK: - Transcription

public struct Transcription: Identifiable, Equatable, Sendable {
    public let id: String
    public var text: String
    public var timestamp: Int64
    public var model: String
    public var audioPath: String?
    public var userId: String
    public var synced: Bool
    /// Recording duration in seconds. Optional for backwards-compat.
    public var duration: TimeInterval?

    // ── V2 additions ──────────────────────────────────────────────────────────
    public var isFavorite: Bool
    public var isPinned: Bool
    public var syncStatus: SyncStatus

    // ── V3 additions ──────────────────────────────────────────────────────────
    /// Last modification time (epoch ms). Used for sorting: newer edits bubble up.
    /// Defaults to timestamp (creation time) when not set.
    public var updatedAt: Int64

    /// Raw Whisper transcript in the spoken language — never overwritten by
    /// grammar correction, AI rewrites, translation, or cloud sync.
    /// Nil for records created before this field was introduced (fall back to text).
    public var rawTranscript: String?

    /// Display-name of the detected spoken language (e.g. "Kannada", "English").
    /// Set at recording time via LanguageDetector. Used to auto-seed the
    /// Output Language dropdown in the AI Rewrite Engine.
    /// Nil for records created before this field was introduced.
    public var detectedLanguage: String?

    /// Effective sort key: the later of updatedAt and timestamp.
    public var effectiveSortDate: Date {
        let ms = max(updatedAt, timestamp)
        return Date(timeIntervalSince1970: TimeInterval(ms) / 1_000)
    }

    public init(
        id: String,
        text: String,
        timestamp: Int64,
        model: String,
        audioPath: String? = nil,
        userId: String,
        synced: Bool = false,
        duration: TimeInterval? = nil,
        isFavorite: Bool = false,
        isPinned: Bool = false,
        syncStatus: SyncStatus = .pending,
        updatedAt: Int64? = nil,
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
}
