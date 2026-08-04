import Foundation

/// Protocol for persistence operations on Transcripts and their versions.
public protocol TranscriptStorageProtocol {
    func saveTranscript(_ transcript: Transcript) throws
    func fetchTranscripts() -> [Transcript]
    func fetchTranscript(id: UUID) -> Transcript?
    func deleteTranscript(id: UUID) throws
    func deleteAllTranscripts() throws
}

/// Service providing non-destructive JSON file-system or UserDefaults persistence for Transcripts and version trees.
public class TranscriptStorage: TranscriptStorageProtocol {
    private let userDefaults: UserDefaults
    private let storageKey = "Echo_Transcripts_Storage_V2"
    
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }
    
    public func saveTranscript(_ transcript: Transcript) throws {
        var transcripts = fetchTranscripts()
        if let index = transcripts.firstIndex(where: { $0.id == transcript.id }) {
            transcripts[index] = transcript
        } else {
            transcripts.insert(transcript, at: 0)
        }
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(transcripts)
        userDefaults.set(data, forKey: storageKey)
    }
    
    public func fetchTranscripts() -> [Transcript] {
        guard let data = userDefaults.data(forKey: storageKey) else {
            return []
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([Transcript].self, from: data)
        } catch {
            print("Error decoding transcripts: \(error)")
            return []
        }
    }
    
    public func fetchTranscript(id: UUID) -> Transcript? {
        return fetchTranscripts().first(where: { $0.id == id })
    }
    
    public func deleteTranscript(id: UUID) throws {
        var transcripts = fetchTranscripts()
        transcripts.removeAll(where: { $0.id == id })
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(transcripts)
        userDefaults.set(data, forKey: storageKey)
    }
    
    public func deleteAllTranscripts() throws {
        userDefaults.removeObject(forKey: storageKey)
    }
}
