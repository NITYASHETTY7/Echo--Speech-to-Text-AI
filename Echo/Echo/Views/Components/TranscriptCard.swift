//
//  TranscriptCard.swift
//  Echo
//
//  Card showing a preview of a saved transcription.
//
//  Matches Android TranscriptionCard:
//  - CardColor (#232329) background
//  - Left icon badge: RecordVoiceOver icon (waveform.and.mic) in primary-tinted rounded box
//  - Text preview (3 lines max, truncated with ellipsis)
//  - Timestamp label below text
//  - Corner radius 20dp / elevation equivalent shadow
//  - ProviderBadge pill (keeps iOS-specific detail)
//

import SwiftUI
import EchoCore

// MARK: - Color tokens (matching Android theme)

extension Color {
    /// #9AA8FF — Echo primary
    static let echoPrimaryCard = Color(red: 0.604, green: 0.659, blue: 1.0)
    /// #232329 — Echo card surface
    static let echoCardSurface = Color(red: 0.137, green: 0.137, blue: 0.161)
    /// #9E9EAE — Echo on-surface variant
    static let echoOnSurfaceVariantCard = Color(red: 0.620, green: 0.620, blue: 0.682)
}

struct TranscriptCard: View {

    let transcription: Transcription

    /// Optional provider identity for the badge.
    var providerId: ProviderId?

    /// Reflects the app's active colour scheme — including a forced theme applied
    /// via `.preferredColorScheme` at RootView. Drives the card's adaptive colours.
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Adaptive colours
    //
    // Light Theme: white card, black title, secondary-gray timestamp.
    // Dark  Theme: existing dark card (#232329), white title, gray timestamp.
    // Shadow, corner radius, icon container, spacing, and layout are unchanged.

    private var cardBackgroundColor: Color {
        colorScheme == .light ? .white : Color.echoCardSurface
    }

    private var titleTextColor: Color {
        // Light: black. Dark: existing `.label` (white on dark).
        colorScheme == .light ? .black : Color(.label)
    }

    private var timestampTextColor: Color {
        // Light: iOS secondaryLabel gray. Dark: existing on-surface variant.
        colorScheme == .light
            ? Color(.secondaryLabel)
            : Color.echoOnSurfaceVariantCard.opacity(0.8)
    }

    // MARK: - Body

    var body: some View {
        HStack(alignment: .top, spacing: 12) {

            // Left icon badge — matches Android "Transcript icon badge" Box
            iconBadge

            // Right column: text + timestamp
            VStack(alignment: .leading, spacing: 6) {
                // Transcript preview (3 lines, ellipsis — matches Android maxLines=3)
                Text(previewText)
                    .font(.subheadline)
                    .foregroundStyle(titleTextColor)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                // Bottom row: timestamp + optional provider badge
                HStack {
                    Text(formattedDate)
                        .font(.caption2)
                        .foregroundStyle(timestampTextColor)

                    Spacer()

                    if let pid = providerId {
                        ProviderBadge(providerId: pid)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 2)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }

    // MARK: - Icon badge (matches Android 40dp box with RecordVoiceOver icon)

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.echoPrimaryCard.opacity(0.12))
                .frame(width: 40, height: 40)

            Image(systemName: "waveform.and.mic")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.echoPrimaryCard)
        }
    }

    // MARK: - Computed display values

    private var previewText: String {
        let trimmed = transcription.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No transcription text." : trimmed
    }

    var formattedDate: String {
        let msec = TimeInterval(transcription.timestamp) / 1_000
        let date = Date(timeIntervalSince1970: msec)
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Formatted recording duration string.
    private var formattedDuration: String {
        guard let seconds = transcription.duration, seconds > 0 else { return "" }
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Preview

#Preview {
    let sample = Transcription(
        id: "preview-1",
        text: "This is an example transcription that was recorded using the Echo app. It may span multiple lines when the content is longer than the visible area of the card.",
        timestamp: Int64(Date().timeIntervalSince1970 * 1_000),
        model: "whisper-large-v3-turbo",
        audioPath: nil,
        userId: "user-1"
    )

    VStack(spacing: 12) {
        TranscriptCard(transcription: sample, providerId: .groq)
        TranscriptCard(transcription: sample, providerId: .openAI)
        TranscriptCard(transcription: sample)
    }
    .padding()
    .background(Color(red: 0.071, green: 0.071, blue: 0.071))
}
