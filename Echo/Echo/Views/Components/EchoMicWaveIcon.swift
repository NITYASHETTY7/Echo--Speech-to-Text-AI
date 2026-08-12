//
//  EchoMicWaveIcon.swift
//  Echo
//
//  SwiftUI replica of the Android ic_echo_mic_wave vector drawable.
//  Original viewport: 48 × 48.  All coordinates are in that space and are
//  scaled to fill whatever `size` is passed in.
//
//  Elements (all white strokes, no fill):
//    • Left waveform  — heartbeat line left of the mic capsule
//    • Right waveform — heartbeat line right of the mic capsule
//    • Mic capsule    — rounded rectangle body (arch top + flat bottom)
//    • Grille lines   — three horizontal lines inside the capsule
//    • Capsule divider— horizontal line at the capsule bottom
//    • Stand          — vertical stem + horizontal base bar
//

import SwiftUI

struct EchoMicWaveIcon: View {

    /// Rendered size (width = height). Defaults to 48 pt to match Android dp size.
    var size: CGFloat = 48
    /// Stroke color. White by default (for use on dark/colored backgrounds).
    var color: Color = .white

    var body: some View {
        Canvas { ctx, canvasSize in
            let s = canvasSize.width / 48.0   // uniform scale factor

            // ── Helper: stroke a path ─────────────────────────────────────
            func stroke(_ path: Path, lineWidth: CGFloat) {
                let style = StrokeStyle(lineWidth: lineWidth * s,
                                        lineCap: .round,
                                        lineJoin: .round)
                ctx.stroke(path, with: .color(color), style: style)
            }

            // ── Left waveform: M1,22 L5,22 L7,14 L9,30 L11.5,18 L13.5,22 L15,22 ──
            var leftWave = Path()
            leftWave.move(to:    CGPoint(x:  1 * s, y: 22 * s))
            leftWave.addLine(to: CGPoint(x:  5 * s, y: 22 * s))
            leftWave.addLine(to: CGPoint(x:  7 * s, y: 14 * s))
            leftWave.addLine(to: CGPoint(x:  9 * s, y: 30 * s))
            leftWave.addLine(to: CGPoint(x: 11.5 * s, y: 18 * s))
            leftWave.addLine(to: CGPoint(x: 13.5 * s, y: 22 * s))
            leftWave.addLine(to: CGPoint(x: 15 * s, y: 22 * s))
            stroke(leftWave, lineWidth: 2.4)

            // ── Right waveform: M33,22 L34.5,22 L36.5,15 L38.5,29 L41,12 L43,22 L47,22 ──
            var rightWave = Path()
            rightWave.move(to:    CGPoint(x: 33 * s, y: 22 * s))
            rightWave.addLine(to: CGPoint(x: 34.5 * s, y: 22 * s))
            rightWave.addLine(to: CGPoint(x: 36.5 * s, y: 15 * s))
            rightWave.addLine(to: CGPoint(x: 38.5 * s, y: 29 * s))
            rightWave.addLine(to: CGPoint(x: 41 * s,   y: 12 * s))
            rightWave.addLine(to: CGPoint(x: 43 * s,   y: 22 * s))
            rightWave.addLine(to: CGPoint(x: 47 * s,   y: 22 * s))
            stroke(rightWave, lineWidth: 2.4)

            // ── Mic capsule: M15,14 A9,9 0 0 1 33,14 L33,24 A9,9 0 0 1 15,24 Z ──
            // The arch is a semicircle from (15,14)→(33,14) with radius 9,
            // sides drop straight to y=24, then a mirrored arch closes back.
            var capsule = Path()
            // Top arc: centre (24,14), radius 9, from 180° to 0° (left to right)
            capsule.addArc(center:     CGPoint(x: 24 * s, y: 14 * s),
                           radius:     9 * s,
                           startAngle: .degrees(180),
                           endAngle:   .degrees(0),
                           clockwise:  false)
            // Right side down
            capsule.addLine(to: CGPoint(x: 33 * s, y: 24 * s))
            // Bottom arc: centre (24,24), radius 9, from 0° to 180° (right to left)
            capsule.addArc(center:     CGPoint(x: 24 * s, y: 24 * s),
                           radius:     9 * s,
                           startAngle: .degrees(0),
                           endAngle:   .degrees(180),
                           clockwise:  false)
            capsule.closeSubpath()
            stroke(capsule, lineWidth: 2.6)

            // ── Grille lines inside capsule (3 horizontal lines) ──
            // M20,8.5 L28,8.5  M20,11.5 L28,11.5  M20,14.5 L28,14.5
            let grillX1: CGFloat = 20, grillX2: CGFloat = 28
            for grillY in [8.5, 11.5, 14.5] as [CGFloat] {
                var line = Path()
                line.move(to:    CGPoint(x: grillX1 * s, y: grillY * s))
                line.addLine(to: CGPoint(x: grillX2 * s, y: grillY * s))
                stroke(line, lineWidth: 1.8)
            }

            // ── Capsule divider: M15.5,22 L32.5,22 ──
            var divider = Path()
            divider.move(to:    CGPoint(x: 15.5 * s, y: 22 * s))
            divider.addLine(to: CGPoint(x: 32.5 * s, y: 22 * s))
            stroke(divider, lineWidth: 1.8)

            // ── Stand stem: M24,33 L24,41 ──
            var stem = Path()
            stem.move(to:    CGPoint(x: 24 * s, y: 33 * s))
            stem.addLine(to: CGPoint(x: 24 * s, y: 41 * s))
            stroke(stem, lineWidth: 2.6)

            // ── Stand base: M18,41.5 L30,41.5 ──
            var base = Path()
            base.move(to:    CGPoint(x: 18 * s, y: 41.5 * s))
            base.addLine(to: CGPoint(x: 30 * s, y: 41.5 * s))
            stroke(base, lineWidth: 2.6)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color(red: 0.0, green: 0.533, blue: 0.533)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .frame(width: 80, height: 80)
        EchoMicWaveIcon(size: 48)
    }
    .padding()
}
