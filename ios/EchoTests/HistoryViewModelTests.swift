import XCTest
@testable import Echo

@MainActor
final class HistoryViewModelTests: XCTestCase {
    
    var userDefaults: UserDefaults!
    var storage: TranscriptStorage!
    var viewModel: HistoryViewModel!
    
    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: "Test_Echo_HistoryVM_\(UUID().uuidString)")!
        storage = TranscriptStorage(userDefaults: userDefaults)
        viewModel = HistoryViewModel(storage: storage)
    }
    
    func testBadgeTypeCalculation() {
        // Original only
        let t1 = Transcript(rawText: "Hello world")
        XCTAssertEqual(t1.badgeType, .originalOnly)
        
        // Grammar Corrected
        let t2 = Transcript(rawText: "hello world", grammarCorrectedText: "Hello world.")
        XCTAssertEqual(t2.badgeType, .grammarCorrected)
        
        // AI Enhanced
        var t3 = Transcript(rawText: "hello world", grammarCorrectedText: "Hello world.")
        t3.addVersion(TranscriptVersion(text: "Hello world email format", type: .preset(.email)))
        XCTAssertEqual(t3.badgeType, .aiEnhanced)
    }
    
    func testMultiVersionSearch() throws {
        var transcript1 = Transcript(rawText: "Discussions regarding quarterly revenue")
        transcript1.addVersion(TranscriptVersion(text: "Action items: send invoice to accounting", type: .preset(.actionItems)))
        
        var transcript2 = Transcript(rawText: "Sprint planning meeting notes")
        transcript2.addVersion(TranscriptVersion(text: "Tasks created in Jira for sprint 42", type: .custom(prompt: "Jira tasks")))
        
        try storage.saveTranscript(transcript1)
        try storage.saveTranscript(transcript2)
        
        viewModel.loadTranscripts()
        
        // Search for text present in non-active version of transcript1 ("invoice")
        viewModel.searchQuery = "invoice"
        XCTAssertEqual(viewModel.filteredTranscripts.count, 1)
        XCTAssertEqual(viewModel.filteredTranscripts.first?.id, transcript1.id)
        
        // Search for text present in transcript2 ("Jira")
        viewModel.searchQuery = "Jira"
        XCTAssertEqual(viewModel.filteredTranscripts.count, 1)
        XCTAssertEqual(viewModel.filteredTranscripts.first?.id, transcript2.id)
        
        // Search matching both
        viewModel.searchQuery = "meeting"
        XCTAssertEqual(viewModel.filteredTranscripts.count, 1)
    }
}
