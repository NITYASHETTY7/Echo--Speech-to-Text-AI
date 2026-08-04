import SwiftUI

/// Component providing horizontal pill tab selector for switching between transcript versions.
public struct VersionSelector: View {
    public let versions: [TranscriptVersion]
    public let activeVersionId: UUID?
    public let onSelectVersion: (UUID) -> Void
    
    public init(
        versions: [TranscriptVersion],
        activeVersionId: UUID?,
        onSelectVersion: @escaping (UUID) -> Void
    ) {
        self.versions = versions
        self.activeVersionId = activeVersionId
        self.onSelectVersion = onSelectVersion
    }
    
    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(versions) { version in
                    let isSelected = version.id == activeVersionId
                    Button(action: {
                        onSelectVersion(version.id)
                    }) {
                        HStack(spacing: 6) {
                            iconForType(version.type)
                                .font(.caption)
                            
                            Text(version.title)
                                .font(.subheadline)
                                .fontWeight(isSelected ? .bold : .regular)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(isSelected ? Color.blue : Color(.secondarySystemBackground))
                        .foregroundColor(isSelected ? .white : .primary)
                        .cornerRadius(20)
                        .shadow(color: isSelected ? Color.blue.opacity(0.3) : Color.clear, radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }
    
    @ViewBuilder
    private func iconForType(_ type: VersionType) -> Image {
        switch type {
        case .original:
            Image(systemName: "mic.fill")
        case .grammarCorrected:
            Image(systemName: "sparkles")
        case .preset(let preset):
            switch preset {
            case .professional: Image(systemName: "briefcase.fill")
            case .meetingNotes: Image(systemName: "doc.text.fill")
            case .summary: Image(systemName: "text.alignleft")
            case .bulletPoints: Image(systemName: "list.bullet")
            case .email: Image(systemName: "envelope.fill")
            case .blogStyle: Image(systemName: "newspaper.fill")
            case .socialMediaPost: Image(systemName: "bubble.left.and.bubble.right.fill")
            case .actionItems: Image(systemName: "checkmark.square.fill")
            }
        case .custom:
            Image(systemName: "wand.and.stars")
        }
    }
}
