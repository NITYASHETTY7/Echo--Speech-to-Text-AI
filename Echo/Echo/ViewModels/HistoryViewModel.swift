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

    /// Transcriptions matching the current searchText (case-insensitive).
    var filteredTranscriptions: [Transcription] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return transcriptions
        }
        let query = searchText.lowercased()
        return transcriptions.filter { $0.text.lowercased().contains(query) }
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
