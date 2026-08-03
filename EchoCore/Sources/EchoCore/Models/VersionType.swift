//
//  VersionType.swift
//  EchoCore
//
//  Mirrors Android's domain.ai.VersionType enum exactly.
//

import Foundation

// MARK: - VersionType

public enum VersionType: String, Codable, CaseIterable, Sendable, Equatable {
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

    /// Human-readable display name shown in UI chips and detail screens.
    public var displayName: String {
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
    public var symbolName: String {
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

    /// True for version types that are AI-generated (not the raw original).
    public var isAIGenerated: Bool {
        self != .original
    }
}
