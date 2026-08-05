//
//  HistoryViewModel.swift
//  Echo
//
//  ViewModel for the transcription history list.
//
//  V2 additions:
//  - toggleFavorite(id:) / togglePin(id:)
//  - filteredTranscriptions now respects search + pin ordering
//

import Foundation
import EchoCore
import os

@MainActor
@Observable
public final class HistoryViewModel {

    // MARK: - Public state

    /// All loaded transcriptions (pinned first, then newest-first within each group).
    private(set) var transcriptions: [Transcription] = []

    /// Search text bound to the search field; filters transcriptions reactively.
    var searchText: String = ""

    /// Transcriptions matching the current searchText (case-insensitive),
    /// always sorted by creation timestamp DESC (newest first) regardless of
    /// any updatedAt / sync reordering in the underlying store.
    var filteredTranscriptions: [Transcription] {
        let base: [Transcription]
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            base = transcriptions
        } else {
            let query = searchText.lowercased()
            base = transcriptions.filter { $0.text.lowercased().contains(query) }
        }
        // Always sort strictly by creation timestamp DESC so history always
        // appears newest-first, independent of updatedAt or sync order.
        return base.sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - Android-matching date groups
    // MARK: - Exact-date groups
    //
    // Each calendar day that has at least one transcription gets its own section.
    // Sections are ordered newest-day first.
    // Today → "Today", yesterday → "Yesterday", all older dates → "Aug 3", "Aug 2", …
    //
    // Sort key: raw `timestamp` (Int64 epoch-ms creation time), newest first.

    /// A named section used on the History screen.
    struct TranscriptionGroup: Identifiable {
        let label: String
        let items: [Transcription]
        var id: String { label }
    }

    /// Transcriptions grouped by exact calendar date, newest section first.
    /// Today → "Today", yesterday → "Yesterday", all older dates → "Aug 3", "Aug 2", …
    /// Filtered by the current searchText; items within each section are newest-first.
    var groupedTranscriptions: [TranscriptionGroup] {
        let base = filteredTranscriptions   // already search-filtered & sorted DESC

        let cal          = Calendar.current
        let now          = Date()
        let startOfToday = cal.startOfDay(for: now)
        let startOfYest  = cal.date(byAdding: .day, value: -1, to: startOfToday)!

        // Label formatter: "Aug 3", "Jul 29", etc.
        let labelFormatter = DateFormatter()
        labelFormatter.dateFormat = "MMM d"

        // Group into ordered buckets keyed by calendar day (startOfDay),
        // preserving newest-day-first order from the sorted input.
        var dayOrder: [Date] = []
        var dayBuckets: [Date: [Transcription]] = [:]

        for t in base {
            let date     = Date(timeIntervalSince1970: TimeInterval(t.timestamp) / 1_000)
            let dayStart = cal.startOfDay(for: date)
            if dayBuckets[dayStart] == nil {
                dayOrder.append(dayStart)
                dayBuckets[dayStart] = []
            }
            dayBuckets[dayStart]!.append(t)
        }

        return dayOrder.compactMap { dayStart -> TranscriptionGroup? in
            guard let items = dayBuckets[dayStart], !items.isEmpty else { return nil }
            let label: String
            if cal.isDate(dayStart, inSameDayAs: startOfToday) {
                label = "Today"
            } else if cal.isDate(dayStart, inSameDayAs: startOfYest) {
                label = "Yesterday"
            } else {
                label = labelFormatter.string(from: dayStart)
            }
            return TranscriptionGroup(label: label, items: items)
        }
    }

    /// Non-nil when a store error should be surfaced.
    private(set) var storeError: Error?

    /// True while loading transcriptions.
    private(set) var isLoading: Bool = false

    // MARK: - Dependencies

    private let store: any TranscriptionStoreProtocol

    // MARK: - Init

    init(store: any TranscriptionStoreProtocol) {
        self.store = store
    }

    // MARK: - Public API

    /// Loads the newest `limit` transcriptions from the store.
    func load(limit: Int = 100) {
        isLoading = true
        storeError = nil
        do {
            transcriptions = try store.fetch(limit: limit)
            EchoLog.ui.debug("HistoryViewModel: loaded \(self.transcriptions.count) transcriptions")
        } catch {
            storeError = error
            EchoLog.ui.error("HistoryViewModel load error: \(error.localizedDescription, privacy: .public)")
        }
        isLoading = false
    }

    /// Deletes the transcription with the given ID and refreshes the list.
    func delete(id: String) {
        do {
            try store.delete(id: id)
            transcriptions.removeAll { $0.id == id }
            EchoLog.ui.debug("HistoryViewModel: deleted \(id, privacy: .public)")
        } catch {
            storeError = error
            EchoLog.ui.error("HistoryViewModel delete error: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Deletes all transcriptions from the store.
    func deleteAll() {
        do {
            try store.deleteAll()
            transcriptions.removeAll()
            EchoLog.ui.debug("HistoryViewModel: deleted all transcriptions")
        } catch {
            storeError = error
            EchoLog.ui.error("HistoryViewModel deleteAll error: \(error.localizedDescription, privacy: .public)")
        }
    }

    // ── V2 ────────────────────────────────────────────────────────────────────

    /// Toggles the favourite flag for the transcription with the given ID.
    func toggleFavorite(id: String) {
        guard let index = transcriptions.firstIndex(where: { $0.id == id }) else { return }
        let newValue = !transcriptions[index].isFavorite
        do {
            try store.setFavorite(id: id, value: newValue)
            transcriptions[index].isFavorite = newValue
            EchoLog.ui.debug("HistoryViewModel: toggleFavorite \(id, privacy: .public) → \(newValue)")
        } catch {
            storeError = error
            EchoLog.ui.error("HistoryViewModel toggleFavorite error: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Toggles the pin flag for the transcription with the given ID.
    func togglePin(id: String) {
        guard let index = transcriptions.firstIndex(where: { $0.id == id }) else { return }
        let newValue = !transcriptions[index].isPinned
        do {
            try store.setPin(id: id, value: newValue)
            transcriptions[index].isPinned = newValue
            // Re-sort locally so pinned items rise to the top immediately.
            // Use effectiveSortDate (max of updatedAt, timestamp) for consistent ordering.
            transcriptions.sort {
                if $0.isPinned != $1.isPinned { return $0.isPinned }
                return $0.effectiveSortDate > $1.effectiveSortDate
            }
            EchoLog.ui.debug("HistoryViewModel: togglePin \(id, privacy: .public) → \(newValue)")
        } catch {
            storeError = error
            EchoLog.ui.error("HistoryViewModel togglePin error: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Clears any surfaced store error.
    func clearError() {
        storeError = nil
    }
}
