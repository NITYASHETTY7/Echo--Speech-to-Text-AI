//
//  PermissionBanner.swift
//  Echo
//
//  Yellow warning banner shown when microphone permission is denied.
//  Reads the real AVAudioApplication permission state and only renders
//  when access is definitely denied. Tapping opens the app's Settings page.
//

import SwiftUI
import EchoCore
import AVFoundation

// MARK: - Conditional banner (auto-hides when permission is granted)

struct PermissionBanner: View {

    @Environment(\.openURL) private var openURL

    // Observe permission on appear and when the app returns to foreground.
    @State private var isDenied: Bool = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if isDenied {
                bannerContent
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isDenied)
        .onAppear { checkPermission() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { checkPermission() }
        }
    }

    // MARK: - Banner layout

    private var bannerContent: some View {
        Button {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            openURL(url)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "mic.slash.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(red: 0.5, green: 0.35, blue: 0.0))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Microphone access denied")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(red: 0.4, green: 0.28, blue: 0.0))

                    Text("Tap to open Settings and enable microphone access.")
                        .font(.caption)
                        .foregroundStyle(Color(red: 0.5, green: 0.35, blue: 0.0))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 0.5, green: 0.35, blue: 0.0))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(red: 1.0, green: 0.93, blue: 0.6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color(red: 0.9, green: 0.78, blue: 0.2).opacity(0.7), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Microphone access denied.")
        .accessibilityHint("Tap to open Settings and enable microphone access for Echo.")
    }

    // MARK: - Permission check

    private func checkPermission() {
        if #available(iOS 17.0, *) {
            isDenied = AVAudioApplication.shared.recordPermission == .denied
        } else {
            isDenied = AVAudioSession.sharedInstance().recordPermission == .denied
        }
    }
}

// MARK: - Preview

#Preview("Denied") {
    VStack {
        // Force-show for preview by wrapping in a container that sets isDenied
        HStack(spacing: 12) {
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(red: 0.5, green: 0.35, blue: 0.0))
            VStack(alignment: .leading, spacing: 2) {
                Text("Microphone access denied")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(red: 0.4, green: 0.28, blue: 0.0))
                Text("Tap to open Settings and enable microphone access.")
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.5, green: 0.35, blue: 0.0))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(red: 0.5, green: 0.35, blue: 0.0))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(red: 1.0, green: 0.93, blue: 0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding()
        Spacer()
    }
}
