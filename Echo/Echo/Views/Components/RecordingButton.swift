//
//  RecordingButton.swift
//  Echo
//
//  Large rounded-square button that mirrors the Android floating pill exactly:
//
//    Shape    — RoundedRectangle(cornerRadius: 20)  (matches Android cornerRadius 20dp)
//    Idle     — teal gradient (#009999 → #008888 → #007979) + ic_echo_mic_wave glyph
//    Recording— deep red  (#C62828)  + stop icon  + pulse ring
//    Paused   — orange               + play icon
//    Processing— grey               + spinner
//

import SwiftUI

// MARK: - Color tokens (Android-matching)

private extension Color {
    /// Idle nude rose — #E1C4BD
    static let echoNude         = Color(red: 0.882, green: 0.769, blue: 0.741)
    /// Idle nude darker variant for gradient end — #C9A49C
    static let echoNudeDark     = Color(red: 0.788, green: 0.643, blue: 0.612)
    /// Recording deep-red  #C62828
    static let echoRecording    = Color(red: 0.776, green: 0.157, blue: 0.157)
    /// Transcribing deep-amber  #E65100
    static let echoTranscribing = Color(red: 0.902, green: 0.318, blue: 0.0)
}

// MARK: - RecordingButtonState

enum RecordingButtonState {
    case idle
    case recording
    case paused
    case processing
}

// MARK: - RecordingButton

struct RecordingButton: View {

    let state: RecordingButtonState
    let action: () -> Void

    @State private var pulseScale:   CGFloat = 1.0
    @State private var pulseOpacity: Double  = 0.6

    // MARK: - Layout constants

    /// Button side length — matches Android PILL_SIZE_DP 56 dp scaled up for a FAB context.
    private let buttonSize: CGFloat = 80
    /// Corner radius — matches Android cornerRadius 20 dp.
    private let cornerRadius: CGFloat = 22

    // MARK: - Body

    var body: some View {
        ZStack {
            // Pulse ring — shown only while recording
            if state == .recording {
                RoundedRectangle(cornerRadius: cornerRadius + 8)
                    .stroke(Color.echoRecording.opacity(pulseOpacity), lineWidth: 3)
                    .frame(width: buttonSize + 16, height: buttonSize + 16)
                    .scaleEffect(pulseScale)
                    .animation(
                        .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                        value: pulseScale
                    )
            }

            // Main button
            Button(action: action) {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(backgroundFill)
                        .frame(width: buttonSize, height: buttonSize)
                        .shadow(color: shadowColor.opacity(0.45), radius: 12, x: 0, y: 6)

                    buttonIcon
                }
            }
            .buttonStyle(.plain)
            .disabled(state == .processing)
        }
        .frame(width: buttonSize + 32, height: buttonSize + 32)
        .onChange(of: state) { _, newState in updatePulse(for: newState) }
        .onAppear { updatePulse(for: state) }
    }

    // MARK: - Background fill

    private var backgroundFill: AnyShapeStyle {
        switch state {
        case .idle:
            return AnyShapeStyle(LinearGradient(
                colors: [.echoNude, .echoNudeDark],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        case .recording:
            return AnyShapeStyle(Color.echoRecording)
        case .paused:
            return AnyShapeStyle(Color.orange)
        case .processing:
            return AnyShapeStyle(Color(.systemGray3))
        }
    }

    private var shadowColor: Color {
        switch state {
        case .idle:       return .echoNude
        case .recording:  return .echoRecording
        case .paused:     return .orange
        case .processing: return .gray
        }
    }

    // MARK: - Icon

    @ViewBuilder
    private var buttonIcon: some View {
        switch state {
        case .idle:
            // Dark taupe icon — readable on the light nude background
            EchoMicWaveIcon(size: buttonSize * 0.72, color: Color(red: 0.42, green: 0.33, blue: 0.31))
        case .recording:
            Image(systemName: "stop.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
        case .paused:
            Image(systemName: "play.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
        case .processing:
            ProgressView()
                .tint(.white)
                .scaleEffect(1.3)
        }
    }

    // MARK: - Pulse animation

    private func updatePulse(for newState: RecordingButtonState) {
        if newState == .recording {
            pulseScale   = 1.2
            pulseOpacity = 0.0
        } else {
            pulseScale   = 1.0
            pulseOpacity = 0.5
        }
    }
}

// MARK: - Previews

#Preview("Idle") {
    ZStack {
        Color.black.ignoresSafeArea()
        RecordingButton(state: .idle, action: {})
    }
}

#Preview("Recording") {
    ZStack {
        Color.black.ignoresSafeArea()
        RecordingButton(state: .recording, action: {})
    }
}

#Preview("Paused") {
    ZStack {
        Color.black.ignoresSafeArea()
        RecordingButton(state: .paused, action: {})
    }
}

#Preview("Processing") {
    ZStack {
        Color.black.ignoresSafeArea()
        RecordingButton(state: .processing, action: {})
    }
}
