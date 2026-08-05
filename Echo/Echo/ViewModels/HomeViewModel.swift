//
//  HomeViewModel.swift
//  Echo
//
//  ViewModel for the Home screen (history-as-main-screen, matching Android MainScreen).
//
//  Exposes:
//  - allTranscriptions: the full history list for display in the LazyVStack
//  - latestTranscription: most recent item (kept for backwards compat / sheet)
//  - isProviderConfigured: drives the ProviderNotConfiguredBanner
//  - currentProvider / currentProviderDisplayName: for the provider row
//

import Foundation
import EchoCore
import os

@MainActor
@Observable
public final class HomeViewModel {

    // MARK: - Public state

    /// All transcriptions, newest first.
    private(set) var allTranscriptions: [Transcription]?

    /// The most recent transcription (first element of allTranscriptions).
    var latestTranscription: Transcription? { allTranscriptions?.first }

    // MARK: - Date-grouped sections (matches HistoryView / Android MainScreen grouping)

    struct TranscriptionGroup: Identifiable {
        let label: String
        let items: [Transcription]
        var id: String { label }
    }

    /// `allTranscriptions` grouped by exact calendar date, newest section first.
    /// Today → "Today", yesterday → "Yesterday", all older dates → "Aug 3", "Aug 2", …
    var groupedTranscriptions: [TranscriptionGroup] {
        guard let all = allTranscriptions, !all.isEmpty else { return [] }

        let cal          = Calendar.current
        let now          = Date()
        let startOfToday = cal.startOfDay(for: now)
        let startOfYest  = cal.date(byAdding: .day, value: -1, to: startOfToday)!

        // Label formatter: "Aug 3", "Jul 29", etc.
        let labelFormatter = DateFormatter()
        labelFormatter.dateFormat = "MMM d"

        // Sort strictly by creation timestamp DESC so newest items appear first.
        let sorted = all.sorted { $0.timestamp > $1.timestamp }

        // Group into an ordered dictionary keyed by calendar day (startOfDay).
        // Using an array of (key, [Transcription]) to preserve newest-day-first order.
        var dayOrder: [Date] = []
        var dayBuckets: [Date: [Transcription]] = [:]

        for t in sorted {
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

    /// True when the current provider has a stored API key.
    /// This is stored as a tracked property (not a computed property) so that
    /// @Observable sees changes to it and redraws the ProviderNotConfiguredBanner
    /// immediately after the user saves an API key in Settings.
    /// Call refreshProviderState() to resync it.
    private(set) var isProviderConfigured: Bool = false

    /// Display name of the currently selected provider.
    var currentProviderDisplayName: String {
        ProviderRegistry.configuration(forRawValue: providerSettings.selectedProvider)?.displayName
            ?? providerSettings.selectedProvider
    }

    /// The ProviderId for the currently selected provider, if valid.
    var currentProvider: ProviderId? {
        ProviderId(rawValue: providerSettings.selectedProvider)
    }

    /// Non-nil when loading fails.
    private(set) var loadError: Error?

    // MARK: - Dependencies

    private let store: any TranscriptionStoreProtocol
    private let providerSettings: ProviderSettings
    private let keychainStore: KeychainStore

    // MARK: - Init

    init(
        store: any TranscriptionStoreProtocol,
        providerSettings: ProviderSettings,
        keychainStore: KeychainStore
    ) {
        self.store = store
        self.providerSettings = providerSettings
        self.keychainStore = keychainStore
        // Set initial provider state synchronously.
        self.isProviderConfigured = Self.checkProviderConfigured(
            keychainStore: keychainStore,
            providerSettings: providerSettings
        )
    }

    // MARK: - Public API

    /// Loads transcriptions for the given owner UID (newest first).
    ///
    /// When `ownerUid` is non-nil only records belonging to that user are
    /// returned — preventing another user's cached records from appearing
    /// immediately after sign-in.  Pass nil (or omit) to load all local
    /// records (guest mode / development).
    ///
    /// Stale history root cause:
    ///   The previous `loadLatest()` called `store.fetch(limit:)` with no UID
    ///   filter.  SwiftData keeps every user's records in the same container, so
    ///   after sign-out / sign-in with a different account the new session saw the
    ///   previous user's cards until a sync completed.  Filtering by ownerUid at
    ///   fetch time means only the signed-in user's rows are ever surfaced in the UI.
    func loadLatest(ownerUid: String? = nil) {
        loadError = nil
        do {
            let all = try store.fetch(limit: 1_000)
            if let uid = ownerUid, !uid.isEmpty, uid != "local" {
                // Signed-in user: show ONLY records belonging to this user.
                //
                // Cross-user leak fix:
                //   The previous filter also included `|| $0.userId == "local"`,
                //   which meant a different user signing in could see the previous
                //   session's guest-stamped ("local") records.  Strict equality on
                //   the UID guarantees User B never sees User A's history.  Guest
                //   recordings are migrated to the signed-in user's UID by the sync
                //   layer's backfill, after which they appear normally.
                allTranscriptions = all.filter { $0.userId == uid }
            } else {
                // Guest mode (no UID): show ONLY local device records.
                // Records stamped with a real UID belong to signed-in users and
                // must never appear in guest mode — this keeps a fresh guest
                // session at the "No transcriptions yet" empty state and prevents
                // a signed-out user from seeing the previous account's history.
                allTranscriptions = all.filter { $0.userId == "local" }
            }
            EchoLog.ui.debug("HomeViewModel: loaded \(self.allTranscriptions?.count ?? 0, privacy: .public) transcriptions for uid=\(ownerUid ?? "guest", privacy: .public)")
        } catch {
            loadError = error
            EchoLog.ui.error("HomeViewModel load error: \(error.localizedDescription, privacy: .public)")
        }
        refreshProviderState()
    }

    /// Immediately clears the in-memory transcript list.
    /// Call this on sign-out so the UI shows an empty state before the
    /// Welcome screen appears — no stale cards are ever visible post-sign-out.
    /// This does NOT delete any data from the local store or Firestore.
    func clearHistory() {
        allTranscriptions = []
        EchoLog.ui.debug("HomeViewModel: history cleared (session reset)")
    }

    /// Refreshes the isProviderConfigured flag.
    /// Call this when returning from Settings so the banner dismisses immediately
    /// — mirrors Android's StateFlow observation of the keystore.
    func refreshProviderState() {
        let newValue = Self.checkProviderConfigured(
            keychainStore: keychainStore,
            providerSettings: providerSettings
        )
        if isProviderConfigured != newValue {
            isProviderConfigured = newValue
        }
    }

    /// Clears any surfaced error.
    func clearError() {
        loadError = nil
    }

    // MARK: - Helpers

    private static func checkProviderConfigured(
        keychainStore: KeychainStore,
        providerSettings: ProviderSettings
    ) -> Bool {
        guard let provider = ProviderId(rawValue: providerSettings.selectedProvider) else { return false }
        return keychainStore.isConfigured(for: provider.rawValue)
    }
}
