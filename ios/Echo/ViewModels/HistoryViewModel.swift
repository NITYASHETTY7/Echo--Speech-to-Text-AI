import Foundation
import Combine

/// ViewModel managing history list, version status badges, and multi-version transcript search.
@MainActor
public class HistoryViewModel: ObservableObject {
    @Published public var transcripts: [Transcript] = []
    @Published public var searchQuery: String = ""
    @Published public var selectedFilter: TranscriptBadgeType? = nil
    
    private let storage: TranscriptStorageProtocol
    
    public init(storage: TranscriptStorageProtocol = TranscriptStorage()) {
        self.storage = storage
        loadTranscripts()
    }
    
    /// Loads all historical transcripts from persistent storage.
    public func loadTranscripts() {
        self.transcripts = storage.fetchTranscripts()
    }
    
    /// Filtered transcripts matching search query across all version texts.
    public var filteredTranscripts: [Transcript] {
        transcripts.filter { transcript in
            // Filter by search query across all versions
            let matchesSearch = transcript.matchesQuery(searchQuery)
            
            // Filter by badge type if filter selected
            if let filter = selectedFilter {
                return matchesSearch && transcript.badgeType == filter
            }
            
            return matchesSearch
        }
    }
    
    /// Deletes a transcript by ID.
    public func deleteTranscript(id: UUID) {
        do {
            try storage.deleteTranscript(id: id)
            loadTranscripts()
        } catch {
            print("Failed to delete transcript: \(error.localizedDescription)")
        }
    }
    
    /// Clears all history.
    public func clearAllHistory() {
        do {
            try storage.deleteAllTranscripts()
            loadTranscripts()
        } catch {
            print("Failed to clear history: \(error.localizedDescription)")
        }
    }
}
