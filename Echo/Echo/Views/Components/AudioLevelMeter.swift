//
//  AudioLevelMeter.swift
//  Echo
//
//  Horizontal bar showing normalised audio level (0.0 – 1.0).
//  Colour transitions smoothly from green → yellow → red as level increases.
//

import SwiftUI
import EchoCore

struct AudioLevelMeter: View {

    /// Normalised audio level in the range 0.0 … 1.0.
    let level: Float

    // MARK: - Layout

    private let barHeight: CGFloat = 8
    private let cornerRadius: CGFloat = 4

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(Color(.systemGray5))
                    .frame(height: barHeight)

                // Fill
                Capsule()
                    .fill(fillColor)
                    .frame(
                        width: max(0, geo.size.width * CGFloat(level)),
                        height: barHeight
                    )
                    .animation(.linear(duration: 0.08), value: level)
            }
        }
        .frame(height: barHeight)
        .accessibilityLabel("Audio level \(Int(level * 100)) percent")
    }

    // MARK: - Colour

    /// Green (low) → yellow (mid) → red (high).
    private var fillColor: Color {
        switch level {
        case ..<0.5:
            // green → yellow
            let t = Double(level / 0.5)
            return Color(
                red: t,
                green: 0.8,
                blue: 0.0
            )
        default:
            // yellow → red
            let t = Double((level - 0.5) / 0.5)
            return Color(
                red: 1.0,
                green: 0.8 * (1.0 - t),
                blue: 0.0
            )
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        AudioLevelMeter(level: 0.0)
        AudioLevelMeter(level: 0.25)
        AudioLevelMeter(level: 0.5)
        AudioLevelMeter(level: 0.75)
        AudioLevelMeter(level: 1.0)
    }
    .padding()
}
