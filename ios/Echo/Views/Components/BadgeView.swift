import SwiftUI

/// Component displaying small colored badges for history items ("Original only", "Grammar Corrected", "AI Enhanced").
public struct BadgeView: View {
    public let badgeType: TranscriptBadgeType
    
    public init(badgeType: TranscriptBadgeType) {
        self.badgeType = badgeType
    }
    
    public var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(badgeColor)
                .frame(width: 6, height: 6)
            
            Text(badgeType.rawValue)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(badgeTextColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(badgeBackgroundColor)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(badgeColor.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var badgeColor: Color {
        switch badgeType {
        case .originalOnly: return .secondary
        case .grammarCorrected: return .blue
        case .aiEnhanced: return .purple
        }
    }
    
    private var badgeTextColor: Color {
        switch badgeType {
        case .originalOnly: return .primary
        case .grammarCorrected: return .blue
        case .aiEnhanced: return .purple
        }
    }
    
    private var badgeBackgroundColor: Color {
        badgeColor.opacity(0.12)
    }
}

#if DEBUG
struct BadgeView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 12) {
            BadgeView(badgeType: .originalOnly)
            BadgeView(badgeType: .grammarCorrected)
            BadgeView(badgeType: .aiEnhanced)
        }
        .padding()
    }
}
#endif
