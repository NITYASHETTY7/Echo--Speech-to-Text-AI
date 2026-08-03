//
//  TranscriptionModel.swift
//  Echo
//
//  SwiftData persistence model.
//
//  Design notes:
//  - @Attribute(.unique) is intentionally absent on iOS 17 (EXC_BREAKPOINT regression).
//  - timestamp is Int (not Int64) to avoid a schema-mismatch assertion on the simulator.
//  - duration is stored as Double (nil represented as 0.0) and surfaced as
//    TimeInterval? in the domain struct. A 0.0 stored value maps back to nil,
//    which preserves backward compatibility with records saved before this field.
//  - V2 additions: isFavorite, isPinned, syncStatus — default values ensure
//    backward compatibility with existing stored records.
//  - V3 additions: updatedAt (defaults to timestamp), rawTranscript.
//

import Foundation
import SwiftData

@Model
final class TranscriptionModel {
    var id: String
    var text: String
    var timestamp: Int       // Int64 on every Apple platform; avoids iOS 17 schema trap
    var model: String
    var audioPath: String?
    var userId: String
    var synced: Bool
    /// Recording duration in seconds. 0.0 means "not recorded" (nil in domain model).
    var duration: Double

    // ── V2 additions ──────────────────────────────────────────────────────────
    /// User-marked favourite. Defaults to false for existing rows.
    var isFavorite: Bool
    /// User-pinned to top. Defaults to false for existing rows.
    var isPinned: Bool
    /// One of "PENDING", "SYNCED", "LOCAL_ONLY", "FAILED".
    var syncStatus: String

    // ── V3 additions ──────────────────────────────────────────────────────────
    /// Last modification time in epoch milliseconds.
    /// Default of 0 lets SwiftData auto-migrate existing rows without a
    /// manual migration plan — the sort logic treats 0 as "use timestamp instead".
    var updatedAt: Int = 0

    /// Raw Whisper transcript in the spoken language — never overwritten by
    /// grammar correction, AI rewrites, translation, or cloud sync.
    var rawTranscript: String?

    /// Display-name of the detected spoken language (e.g. "Kannada").
    /// Nil for records created before this field was introduced.
    var detectedLanguage: String?

    init(
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

    convenience init(_ transcription: Transcription) {
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

    var domainValue: Transcription {
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
