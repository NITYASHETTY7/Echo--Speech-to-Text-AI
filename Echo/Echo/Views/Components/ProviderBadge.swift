//
//  ProviderBadge.swift
//  Echo
//
//  Small pill label showing the name of a provider.
//  Each provider gets a distinct tint colour for quick visual identification.
//

import SwiftUI
import EchoCore

struct ProviderBadge: View {

    let providerId: ProviderId

    // MARK: - Body

    var body: some View {
        Text(providerId.displayName)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(tintColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tintColor.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(tintColor.opacity(0.3), lineWidth: 0.5))
    }

    // MARK: - Per-provider colour

    private var tintColor: Color {
        switch providerId {
        case .groq:       return Color(red: 0.96, green: 0.49, blue: 0.0)   // orange
        case .openAI:     return Color(red: 0.1,  green: 0.74, blue: 0.61)  // teal
        case .openRouter: return Color(red: 0.42, green: 0.31, blue: 0.89)  // purple
        case .deepgram:   return Color(red: 0.08, green: 0.47, blue: 0.95)  // blue
        case .assemblyAI: return Color(red: 0.92, green: 0.25, blue: 0.47)  // rose
        case .gemini:     return Color(red: 0.20, green: 0.66, blue: 0.32)  // green
        case .azure:      return Color(red: 0.0,  green: 0.45, blue: 0.78)  // azure blue
        case .custom:     return Color(.systemGray)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 10) {
        ForEach(ProviderId.allCases, id: \.self) { id in
            ProviderBadge(providerId: id)
        }
    }
    .padding()
}
