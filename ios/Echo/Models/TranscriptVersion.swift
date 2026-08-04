import Foundation

/// Represents a single immutable version of a transcript.
public struct TranscriptVersion: Identifiable, Codable, Equatable, Hashable {
    public let id: UUID
    public let timestamp: Date
    public let text: String
    public let type: VersionType
    public let title: String
    public let metadata: [String: String]?
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        text: String,
        type: VersionType,
        title: String? = nil,
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.type = type
        self.title = title ?? type.description
        self.metadata = metadata
    }
}
