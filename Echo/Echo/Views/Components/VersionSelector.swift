//
//  VersionSelector.swift
//  Echo
//
//  Horizontal scrollable version chips.
//  Mirrors Android's VersionSelector composable exactly:
//  - Chip per version, tapping sets active index
//  - Original: mic (outlined) icon; AI versions: sparkles (filled) icon
//  - Active chip: linear gradient background
//  - Inactive chip: card background + 1dp outline border
//  - Single version: "Original Transcript" header row (no chips)
//

import SwiftUI
import EchoCore

struct VersionSelector: View {

    let versions: [TranscriptVersion]
    let activeIndex: Int
    let onSelectIndex: (Int) -> Void

    var body: some View {
        if versions.isEmpty {
            EmptyView()
        } else if versions.count == 1 {
            singleVersionHeader
        } else {
            scrollableChips
        }
    }

    // ── Single version header (Android: plain Row with Mic icon + "Original Transcript") ──

    private var singleVersionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "mic")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.accentColor)
            Text("Original Transcript")
                .font(.subheadline.weight(.semibold))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // ── Scrollable chips (Android: horizontal Row, 8dp spacing) ──────────────

    private var scrollableChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(versions.enumerated()), id: \.element.id) { index, version in
                    VersionChip(
                        version: version,
                        isSelected: index == activeIndex,
                        onTap: { onSelectIndex(index) }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - VersionChip

private struct VersionChip: View {
    let version: TranscriptVersion
    let isSelected: Bool
    let onTap: () -> Void

    /// Time string — "HH:mm". Hides timestamp if createdAt is zero (synthetic
    /// placeholder before real metadata is available).
    private var timeString: String? {
        guard version.createdAt > 0 else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(version.createdAt) / 1_000)
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                // Icon: mic for Original, sparkles for all AI versions (Android parity)
                Image(systemName: version.versionType == .original ? "mic" : "sparkles")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? .white : Color.accentColor)

                Text(version.versionType.displayName)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : Color(.secondaryLabel))

                // Timestamp — shown only when valid (Android: "• HH:mm")
                if let time = timeString {
                    Text("• \(time)")
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : Color(.tertiaryLabel))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.75)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                } else {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(Color(.separator), lineWidth: 1)
                        )
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}
