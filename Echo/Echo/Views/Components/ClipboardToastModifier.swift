//
//  ClipboardToastModifier.swift
//  Echo
//
//  Lightweight non-blocking banner shown when a transcript is copied to the
//  clipboard because no editable UITextInput was active.
//
//  Design:
//  • Slides in from the top of the safe area.
//  • Auto-dismisses after a fixed duration.
//  • Never blocks interaction (pointer-events pass through).
//  • Not an alert — matches Android's Toast / Snackbar style.
//  • Can be triggered by any parent view via a simple .clipboardToast(isPresented:)
//    modifier so the call site stays clean.
//

import SwiftUI

// MARK: - ClipboardToastModifier

private struct ClipboardToastModifier: ViewModifier {

    @Binding var isPresented: Bool

    private let message: String
    private let autoDismissAfter: TimeInterval

    init(isPresented: Binding<Bool>,
         message: String = "Transcript copied to clipboard",
         autoDismissAfter: TimeInterval = 2.5) {
        self._isPresented    = isPresented
        self.message         = message
        self.autoDismissAfter = autoDismissAfter
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if isPresented {
                    toastBanner
                        .transition(
                            .asymmetric(
                                insertion:  .move(edge: .top).combined(with: .opacity),
                                removal:    .move(edge: .top).combined(with: .opacity)
                            )
                        )
                        // Auto-dismiss
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + autoDismissAfter) {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    isPresented = false
                                }
                            }
                        }
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isPresented)
    }

    // MARK: - Banner shape

    private var toastBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(
            Capsule()
                .fill(Color(red: 0.13, green: 0.13, blue: 0.16).opacity(0.92))
                .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 4)
        )
        .padding(.top, 12)           // gap below the navigation bar
        .allowsHitTesting(false)     // never blocks taps beneath the toast
        .accessibilityLabel(message)
    }
}

// MARK: - View extension

extension View {
    /// Presents a lightweight clipboard toast banner.
    ///
    /// - Parameters:
    ///   - isPresented: Binding driven to `true` to show the toast. The modifier
    ///     resets it to `false` automatically after `autoDismissAfter` seconds.
    ///   - message: Text displayed in the banner.
    func clipboardToast(
        isPresented: Binding<Bool>,
        message: String = "Transcript copied to clipboard"
    ) -> some View {
        modifier(ClipboardToastModifier(isPresented: isPresented, message: message))
    }
}
