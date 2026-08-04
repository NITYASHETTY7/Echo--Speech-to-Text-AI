import Foundation

/// History badge status for transcript.
public enum TranscriptBadgeType: String, Codable, CaseIterable {
    case originalOnly = "Original only"
    case grammarCorrected = "Grammar Corrected"
    case aiEnhanced = "AI Enhanced"
    
    public var badgeColorName: String {
        switch self {
        case .originalOnly: return "gray"
        case .grammarCorrected: return "blue"
        case .aiEnhanced: return "purple"
        }
    }
}

/// Core domain entity for a transcription session containing one or more transcript versions.
public struct Transcript: Identifiable, Codable, Equatable {
    public let id: UUID
    public let createdAt: Date
    public var updatedAt: Date
    public var versions: [TranscriptVersion]
    public var activeVersionId: UUID
    public var audioPath: String?
    
    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        versions: [TranscriptVersion],
        activeVersionId: UUID? = nil,
        audioPath: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.versions = versions
        self.activeVersionId = activeVersionId ?? versions.first?.id ?? UUID()
        self.audioPath = audioPath
    }
    
    /// Helper initializer for creating a transcript with a raw initial string.
    public init(rawText: String, grammarCorrectedText: String? = nil, audioPath: String? = nil) {
        self.id = UUID()
        self.createdAt = Date()
        self.updatedAt = Date()
        self.audioPath = audioPath
        
        let original = TranscriptVersion(text: rawText, type: .original)
        var initialVersions = [original]
        
        if let corrected = grammarCorrectedText, !corrected.isEmpty, corrected != rawText {
            let correctedVersion = TranscriptVersion(text: corrected, type: .grammarCorrected)
            initialVersions.append(correctedVersion)
            self.activeVersionId = correctedVersion.id
        } else {
            self.activeVersionId = original.id
        }
        
        self.versions = initialVersions
    }
    
    /// Returns active transcript version.
    public var activeVersion: TranscriptVersion? {
        versions.first(where: { $0.id == activeVersionId }) ?? versions.last
    }
    
    /// Returns raw original transcript version.
    public var originalVersion: TranscriptVersion? {
        versions.first(where: { $0.type == .original })
    }
    
    /// Checks if transcript contains a grammar corrected version.
    public var hasGrammarCorrection: Bool {
        versions.contains(where: { $0.type == .grammarCorrected })
    }
    
    /// Checks if transcript contains any AI rewrite versions.
    public var hasAIRewrite: Bool {
        versions.contains(where: {
            if case .preset = $0.type { return true }
            if case .custom = $0.type { return true }
            return false
        })
    }
    
    /// Badge type for history display.
    public var badgeType: TranscriptBadgeType {
        if hasAIRewrite {
            return .aiEnhanced
        } else if hasGrammarCorrection {
            return .grammarCorrected
        } else {
            return .originalOnly
        }
    }
    
    /// Mutating helper to append a new version and set it active.
    public mutating func addVersion(_ version: TranscriptVersion) {
        versions.append(version)
        activeVersionId = version.id
        updatedAt = Date()
    }
    
    /// Multi-version search matching helper.
    public func matchesQuery(_ query: String) -> Bool {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
        let lowerQuery = query.lowercased()
        return versions.contains { $0.text.lowercased().contains(lowerQuery) }
    }
}
