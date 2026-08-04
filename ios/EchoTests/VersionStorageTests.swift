import XCTest
@testable import Echo

final class VersionStorageTests: XCTestCase {
    
    var userDefaults: UserDefaults!
    var storage: TranscriptStorage!
    
    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: "Test_Echo_Storage_\(UUID().uuidString)")!
        storage = TranscriptStorage(userDefaults: userDefaults)
    }
    
    func testSaveAndRetrieveTranscriptWithVersions() throws {
        var transcript = Transcript(rawText: "Raw speech text", grammarCorrectedText: "Raw speech text corrected.")
        
        let rewriteVersion = TranscriptVersion(text: "Executive Summary: Raw speech text.", type: .preset(.summary))
        transcript.addVersion(rewriteVersion)
        
        try storage.saveTranscript(transcript)
        
        let fetched = storage.fetchTranscript(id: transcript.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.versions.count, 3) // Original, Grammar Corrected, Summary
        XCTAssertEqual(fetched?.activeVersionId, rewriteVersion.id)
        XCTAssertEqual(fetched?.activeVersion?.text, "Executive Summary: Raw speech text.")
    }
    
    func testVersionSwitchingPreservesAllVersions() {
        var transcript = Transcript(rawText: "Original raw audio transcript")
        let version2 = TranscriptVersion(text: "Professional version", type: .preset(.professional))
        let version3 = TranscriptVersion(text: "Email version", type: .preset(.email))
        
        transcript.addVersion(version2)
        transcript.addVersion(version3)
        
        XCTAssertEqual(transcript.versions.count, 3)
        XCTAssertEqual(transcript.activeVersionId, version3.id)
        
        // Switch back to Original
        if let original = transcript.originalVersion {
            transcript.activeVersionId = original.id
            XCTAssertEqual(transcript.activeVersion?.text, "Original raw audio transcript")
        }
        
        // Ensure no data was lost
        XCTAssertEqual(transcript.versions.count, 3)
    }
    
    func testDeleteTranscript() throws {
        let transcript = Transcript(rawText: "Test transcript to delete")
        try storage.saveTranscript(transcript)
        
        XCTAssertEqual(storage.fetchTranscripts().count, 1)
        
        try storage.deleteTranscript(id: transcript.id)
        XCTAssertEqual(storage.fetchTranscripts().count, 0)
    }
}
