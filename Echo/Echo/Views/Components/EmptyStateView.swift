//
//  EmptyStateView.swift
//  Echo
//
//  Centred empty-state illustration with an icon, title, subtitle,
//  and an optional primary action button.
//

import SwiftUI
import EchoCore

struct EmptyStateView: View {

    let systemImage: String
    let title: String
    let subtitle: String

    /// When non-nil an action button is shown below the subtitle.
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    // MARK: - Body

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: systemImage)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)

            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.white)
                }
                .padding(.top, 4)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
    }
}

// MARK: - Preview

#Preview("With action") {
    EmptyStateView(
        systemImage: "waveform.slash",
        title: "No Transcriptions Yet",
        subtitle: "Tap the mic button to record something and your transcriptions will appear here.",
        actionTitle: "Start Recording",
        action: {}
    )
}

#Preview("Without action") {
    EmptyStateView(
        systemImage: "magnifyingglass",
        title: "No Results",
        subtitle: "Try a different search term."
    )
}
