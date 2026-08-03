//
//  Transcription.swift
//  Echo
//
//  Domain representation of a saved transcription.
//  Fields mirror Android's domain.model.Transcription.
//  Added in V2: isFavorite, isPinned, syncStatus
//  Added in V3: updatedAt (epoch ms), rawTranscript, detectedLanguage
//

import Foundation

// MARK: - SyncStatus

/// Mirrors Android's "PENDING" / "SYNCED" / "LOCAL_ONLY" string constants.
enum SyncStatus: String, Codable, Sendable {
    case pending    = "PENDING"
    case synced     = "SYNCED"
    case localOnly  = "LOCAL_ONLY"
    case failed     = "FAILED"
}

// MARK: - Transcription

struct Transcription: Identifiable, Equatable, Sendable {
    let id: String
    var text: String
    var timestamp: Int64
    var model: String
    var audioPath: String?
    var userId: String
    var synced: Bool
    /// Recording duration in seconds. Optional for backwards-compat.
    var duration: TimeInterval?

    // ── V2 additions ──────────────────────────────────────────────────────────
    var isFavorite: Bool
    var isPinned: Bool
    var syncStatus: SyncStatus

    // ── V3 additions ──────────────────────────────────────────────────────────
    /// Last modification time (epoch ms). Used for sorting.
    var updatedAt: Int64

    /// Raw Whisper transcript in the spoken language.
    var rawTranscript: String?

    /// Display-name of the detected spoken language (e.g. "Kannada", "English").
    /// Used to auto-seed the Output Language dropdown in the AI Rewrite Engine.
    var detectedLanguage: String?

    /// Effective sort key: the later of updatedAt and timestamp.
    var effectiveSortDate: Date {
        let ms = max(updatedAt, timestamp)
        return Date(timeIntervalSince1970: TimeInterval(ms) / 1_000)
    }

    init(
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
