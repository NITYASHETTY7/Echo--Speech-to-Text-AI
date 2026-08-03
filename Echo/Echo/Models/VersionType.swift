//
//  VersionType.swift
//  Echo
//
//  Mirrors Android's domain.ai.VersionType enum exactly.
//  Each case represents a distinct AI processing stage for a transcript.
//

import Foundation

// MARK: - VersionType

enum VersionType: String, Codable, CaseIterable, Sendable, Equatable {
    case original         = "Original"
    case grammarCorrected = "GrammarCorrected"
    case autoEnhanced     = "AutoEnhanced"
    case professional     = "Professional"
    case summary          = "Summary"
    case meetingNotes     = "MeetingNotes"
    case email            = "Email"
    case bulletPoints     = "BulletPoints"
    case translation      = "Translation"
    case custom           = "Custom"

    /// Human-readable display name shown in VersionSelector chips and detail screens.
    var displayName: String {
        switch self {
        case .original:         return "Original"
        case .grammarCorrected: return "Grammar Corrected"
        case .autoEnhanced:     return "AI Enhanced"
        case .professional:     return "Professional"
        case .summary:          return "Summary"
        case .meetingNotes:     return "Meeting Notes"
        case .email:            return "Email"
        case .bulletPoints:     return "Bullet Points"
        case .translation:      return "Translation"
        case .custom:           return "Custom Rewrite"
        }
    }

    /// SF Symbol name that represents this version type in the UI.
    var symbolName: String {
        switch self {
        case .original:         return "mic"
        case .grammarCorrected: return "checkmark.circle"
        case .autoEnhanced:     return "sparkles"
        case .professional:     return "briefcase"
        case .summary:          return "doc.text"
        case .meetingNotes:     return "note.text"
        case .email:            return "envelope"
        case .bulletPoints:     return "list.bullet"
        case .translation:      return "globe"
        case .custom:           return "pencil.and.list.clipboard"
        }
    }

    /// True for version types that are AI-generated (i.e. not the raw original).
    var isAIGenerated: Bool {
        self != .original
    }
}
