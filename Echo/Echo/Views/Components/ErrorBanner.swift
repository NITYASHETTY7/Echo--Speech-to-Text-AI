//
//  ErrorBanner.swift
//  Echo
//
//  Dismissible red error banner shown at the top of a screen.
//  Fades in when `message` is non-nil; tapping the ✕ dismisses it.
//

import SwiftUI
import EchoCore

struct ErrorBanner: View {

    /// Bind to a `String?` in your parent view.
    /// Set to `nil` to hide, non-nil to show.
    @Binding var message: String?

    // MARK: - Body

    var body: some View {
        if let text = message {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)

                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        message = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(6)
                        .background(Color.white.opacity(0.15), in: Circle())
                }
                .accessibilityLabel("Dismiss error")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(red: 0.82, green: 0.12, blue: 0.12))
            .cornerRadius(12)
            .shadow(color: Color.red.opacity(0.3), radius: 6, x: 0, y: 3)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Error: \(text)")
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var msg: String? = "Could not connect to the Groq API. Please check your API key and try again."

    VStack(alignment: .leading) {
        ErrorBanner(message: $msg)
            .padding(.horizontal)

        Button("Toggle error") {
            withAnimation {
                msg = msg == nil ? "Something went wrong." : nil
            }
        }
        .padding()

        Spacer()
    }
    .background(Color(.systemGroupedBackground))
}
