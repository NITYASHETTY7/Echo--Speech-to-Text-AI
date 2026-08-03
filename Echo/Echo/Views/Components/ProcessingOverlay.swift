//
//  ProcessingOverlay.swift
//  Echo
//
//  Full-screen overlay that shows step-by-step transcription progress.
//  Driven by TranscriptionProgress (from TranscriptionPipeline.swift).
//

import SwiftUI
import EchoCore

// MARK: - Step status (file-private so both views share one type)

private enum PipelineStepStatus {
    case pending, active, done
}

// MARK: - Overlay

struct ProcessingOverlay: View {

    /// The current pipeline stage, or nil when not shown.
    let progress: TranscriptionProgress?

    /// Called when the user taps the Cancel button.
    var onCancel: (() -> Void)?

    // MARK: - Steps configuration

    private let steps: [(stage: TranscriptionProgress, label: String, icon: String)] = [
        (.preparing,  "Preparing",  "waveform"),
        (.uploading,  "Uploading",  "arrow.up.circle"),
        (.processing, "Processing", "gearshape"),
        (.filtering,  "Filtering",  "sparkles"),
        (.completed,  "Completed",  "checkmark.circle"),
    ]

    // MARK: - Body

    var body: some View {
        if progress != nil {
            ZStack {
                // Dimmed background
                Color.black.opacity(0.55)
                    .ignoresSafeArea()

                // GeometryReader lets the card adapt its max height to the
                // available screen space, preventing clipping on iPhone SE.
                GeometryReader { geo in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 24) {
                            Text("Transcribing…")
                                .font(.headline)
                                .foregroundStyle(.primary)

                            // Step list
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(steps, id: \.label) { step in
                                    PipelineStepRow(
                                        icon: step.icon,
                                        label: step.label,
                                        status: rowStatus(for: step.stage)
                                    )
                                }
                            }

                            // Cancel button
                            if let onCancel {
                                Button("Cancel", action: onCancel)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(28)
                        .frame(minWidth: 0, maxWidth: .infinity)
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                    // Constrain card width and cap height so it never overflows
                    .frame(
                        maxWidth: geo.size.width - 80,   // same as .padding(.horizontal, 40)
                        maxHeight: geo.size.height * 0.75
                    )
                    // Centre the card in the available space
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            .animation(.easeInOut(duration: 0.25), value: progress)
        }
    }

    // MARK: - Helpers

    private func rowStatus(for stage: TranscriptionProgress) -> PipelineStepStatus {
        guard let current = progress else { return .pending }
        let currentIndex = steps.firstIndex(where: { $0.stage == current }) ?? 0
        let stageIndex   = steps.firstIndex(where: { $0.stage == stage   }) ?? 0

        if stageIndex < currentIndex  { return .done   }
        if stageIndex == currentIndex { return .active  }
        return .pending
    }
}

// MARK: - Step row

private struct PipelineStepRow: View {

    let icon: String
    let label: String
    let status: PipelineStepStatus

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(circleColor)
                    .frame(width: 32, height: 32)

                if status == .active {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: status == .done ? "checkmark" : icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }

            Text(label)
                .font(.subheadline)
                .fontWeight(status == .active ? .semibold : .regular)
                .foregroundStyle(status == .pending ? Color.secondary : Color.primary)

            Spacer()
        }
    }

    private var circleColor: Color {
        switch status {
        case .pending: return Color(.systemGray4)
        case .active:  return .accentColor
        case .done:    return .green
        }
    }
}

// MARK: - Preview

#Preview("Processing") {
    ZStack {
        Color(.systemBackground).ignoresSafeArea()
        Text("Content behind overlay")
        ProcessingOverlay(progress: .processing, onCancel: {})
    }
}

#Preview("Completed") {
    ZStack {
        Color(.systemBackground).ignoresSafeArea()
        ProcessingOverlay(progress: .completed, onCancel: nil)
    }
}

#Preview("Hidden") {
    ZStack {
        Color(.systemBackground).ignoresSafeArea()
        Text("No overlay shown")
        ProcessingOverlay(progress: nil, onCancel: nil)
    }
}
