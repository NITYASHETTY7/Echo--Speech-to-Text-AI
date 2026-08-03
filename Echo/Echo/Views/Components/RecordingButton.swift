//
//  RecordingButton.swift
//  Echo
//
//  Large circular button that is aware of recording state.
//  Shows a pulsing ring animation when actively recording.
//

import SwiftUI
import EchoCore

/// The visual state the button renders for.
enum RecordingButtonState {
    case idle
    case recording
    case paused
    case processing
}

struct RecordingButton: View {

    let state: RecordingButtonState
    let action: () -> Void

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.6

    // MARK: - Layout constants

    private let buttonSize: CGFloat = 80
    private let ringInset: CGFloat = -12

    // MARK: - Body

    var body: some View {
        ZStack {
            // Pulse ring — visible only while recording
            if state == .recording {
                Circle()
                    .stroke(Color.red.opacity(pulseOpacity), lineWidth: 3)
                    .frame(width: buttonSize - ringInset * 2,
                           height: buttonSize - ringInset * 2)
                    .scaleEffect(pulseScale)
                    .animation(
                        .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                        value: pulseScale
                    )
            }

            // Main button circle
            Button(action: action) {
                ZStack {
                    Circle()
                        .fill(backgroundColor)
                        .frame(width: buttonSize, height: buttonSize)
                        .shadow(color: shadowColor.opacity(0.4), radius: 8, x: 0, y: 4)

                    buttonIcon
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .disabled(state == .processing)
        }
        .frame(width: buttonSize + 28, height: buttonSize + 28) // leave room for ring
        .onChange(of: state) { _, newState in
            updatePulse(for: newState)
        }
        .onAppear {
            updatePulse(for: state)
        }
    }

    // MARK: - Derived visuals

    private var backgroundColor: Color {
        switch state {
        case .idle:       return .red
        case .recording:  return .red
        case .paused:     return .orange
        case .processing: return Color(.systemGray3)
        }
    }

    private var shadowColor: Color {
        switch state {
        case .idle, .recording: return .red
        case .paused:           return .orange
        case .processing:       return .gray
        }
    }

    @ViewBuilder
    private var buttonIcon: some View {
        switch state {
        case .idle:
            Image(systemName: "mic.fill")
        case .recording:
            Image(systemName: "stop.fill")
        case .paused:
            Image(systemName: "play.fill")
        case .processing:
            ProgressView()
                .tint(.white)
                .scaleEffect(1.3)
        }
    }

    // MARK: - Animation helpers

    private func updatePulse(for newState: RecordingButtonState) {
        if newState == .recording {
            pulseScale = 1.25
            pulseOpacity = 0.0
        } else {
            pulseScale = 1.0
            pulseOpacity = 0.6
        }
    }
}

// MARK: - Preview

#Preview("Idle") {
    RecordingButton(state: .idle, action: {})
}

#Preview("Recording") {
    RecordingButton(state: .recording, action: {})
}

#Preview("Paused") {
    RecordingButton(state: .paused, action: {})
}

#Preview("Processing") {
    RecordingButton(state: .processing, action: {})
}
