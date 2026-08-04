import Foundation

/// Encapsulates the output of an AI rewrite operation.
public struct RewriteResult: Equatable, Codable {
    public let originalText: String
    public let rewrittenText: String
    public let promptUsed: String
    public let versionCreated: TranscriptVersion
    public let timestamp: Date
    
    public init(
        originalText: String,
        rewrittenText: String,
        promptUsed: String,
        versionCreated: TranscriptVersion,
        timestamp: Date = Date()
    ) {
        self.originalText = originalText
        self.rewrittenText = rewrittenText
        self.promptUsed = promptUsed
        self.versionCreated = versionCreated
        self.timestamp = timestamp
    }
}
