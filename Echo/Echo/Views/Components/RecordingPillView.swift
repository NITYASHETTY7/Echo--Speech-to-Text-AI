//
//  RecordingPillView.swift
//  Echo
//
//  Inline recording capsule shown on the Home screen while a recording session
//  is active. Displays live audio level, elapsed duration, stop and cancel.
//  Previously defined inline inside HomeView; extracted here so both the
//  static-FAB path (HomeView) and the FloatingPillView can reference it.
//

import SwiftUI
import EchoCore

// MARK: - Color tokens

private extension Color {
    static let pillPrimary        = Color(red: 0.604, green: 0.659, blue: 1.0)
    static let pillPrimaryVariant = Color(red: 0.486, green: 0.549, blue: 1.0)
}

// MARK: - RecordingPillView

struct RecordingPillView: View {

    let viewModel: RecordingViewModel
    let onStop: () -> Void
    let onCancel: () -> Void
    let onTranscriptReady: (Transcription) -> Void
    let onError: () -> Void

    @Environment(\.transcriptionStore) private var transcriptionStore

    // Explicit memberwise init required: the struct is internal and Swift's
    // synthesised init for stored properties includes the @Environment property
    // wrapper which cannot be passed by callers.
    init(
        viewModel: RecordingViewModel,
        onStop: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onTranscriptReady: @escaping (Transcription) -> Void,
        onError: @escaping () -> Void
    ) {
        self.viewModel         = viewModel
        self.onStop            = onStop
        self.onCancel          = onCancel
        self.onTranscriptReady = onTranscriptReady
        self.onError           = onError
    }

    var body: some View {
        HStack(spacing: 12) {

            // Cancel
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .disabled(viewModel.isTranscribing)
            .accessibilityLabel("Cancel recording")

            // Waveform / progress
            if viewModel.isTranscribing {
                ProgressView().tint(.white).scaleEffect(0.85).frame(width: 28, height: 28)
            } else {
                AudioLevelMeter(level: viewModel.audioLevel)
                    .frame(width: 40, height: 20)
            }

            // Duration / status
            VStack(alignment: .leading, spacing: 0) {
                if viewModel.isTranscribing {
                    Text("Transcribing…")
                        .font(.caption.weight(.semibold)).foregroundStyle(.white)
                } else {
                    Text(formattedDuration)
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.white).monospacedDigit()
                    Text(stateLabel)
                        .font(.caption2).foregroundStyle(.white.opacity(0.75))
                }
            }
            .frame(minWidth: 70, alignment: .leading)

            Spacer(minLength: 0)

            // Stop
            Button(action: onStop) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.2)).frame(width: 40, height: 40)
                    Image(systemName: "stop.fill")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                }
            }
            .disabled(!viewModel.isRecording && !viewModel.isPaused)
            .accessibilityLabel("Stop recording")
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(
            Capsule()
                .fill(LinearGradient(
                    colors: [.pillPrimary, .pillPrimaryVariant],
                    startPoint: .leading, endPoint: .trailing
                ))
                .shadow(color: Color.pillPrimary.opacity(0.5), radius: 12, x: 0, y: 6)
        )
        .frame(maxWidth: 320)
        .onChange(of: viewModel.transcriptionState) { _, newState in
            if case .completed(let response) = newState {
                if let store = transcriptionStore,
                   let match = try? store.fetch(limit: 200).first(where: { $0.text == response.text }) {
                    onTranscriptReady(match)
                } else {
                    let synthetic = Transcription(
                        id: UUID().uuidString,
                        text: response.text,
                        timestamp: Int64(Date().timeIntervalSince1970 * 1_000),
                        model: response.model,
                        audioPath: nil,
                        userId: "local"
                    )
                    onTranscriptReady(synthetic)
                }
            }
            if case .failed = newState { onError() }
        }
        .onChange(of: viewModel.recordingState) { _, state in
            if case .failed = state { onError() }
        }
    }

    private var formattedDuration: String {
        let total = Int(viewModel.duration)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var stateLabel: String {
        if viewModel.isRecording { return "Recording" }
        if viewModel.isPaused    { return "Paused" }
        return "Ready"
    }
}
