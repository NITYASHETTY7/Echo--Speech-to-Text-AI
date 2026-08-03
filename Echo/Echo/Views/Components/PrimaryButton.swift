//
//  PrimaryButton.swift
//  Echo
//
//  Full-width styled primary action button.
//  Supports a loading state and a disabled state.
//

import SwiftUI
import EchoCore

struct PrimaryButton: View {

    let title: String
    let action: () -> Void

    var isLoading: Bool = false
    var isDisabled: Bool = false
    var systemImage: String? = nil

    // MARK: - Body

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.9)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                }

                Text(title)
                    .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .foregroundStyle(.white)
            .background(
                isDisabled
                    ? Color(.systemGray3)
                    : Color.accentColor,
                in: RoundedRectangle(cornerRadius: 14)
            )
        }
        .disabled(isDisabled || isLoading)
        .animation(.easeInOut(duration: 0.15), value: isDisabled)
        .accessibilityLabel(title)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        PrimaryButton(title: "Start Recording", action: {}, systemImage: "mic.fill")
        PrimaryButton(title: "Loading…", action: {}, isLoading: true)
        PrimaryButton(title: "Disabled", action: {}, isDisabled: true)
    }
    .padding()
}
