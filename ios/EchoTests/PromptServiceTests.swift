import XCTest
@testable import Echo

final class PromptServiceTests: XCTestCase {
    
    var userDefaults: UserDefaults!
    var service: PromptService!
    
    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: "Test_Echo_PromptService_\(UUID().uuidString)")!
        service = PromptService(userDefaults: userDefaults)
    }
    
    override func tearDown() {
        userDefaults.removePersistentDomain(forName: "Test_Echo_PromptService")
        super.tearDown()
    }
    
    func testDefaultTemplatesAreLoaded() {
        let templates = service.getTemplates()
        XCTAssertGreaterThanOrEqual(templates.count, 6)
        
        let titles = templates.map { $0.title }
        XCTAssertTrue(titles.contains("Professional"))
        XCTAssertTrue(titles.contains("Summary"))
        XCTAssertTrue(titles.contains("Meeting Notes"))
        XCTAssertTrue(titles.contains("Bullet Points"))
        XCTAssertTrue(titles.contains("Email"))
        XCTAssertTrue(titles.contains("Action Items"))
    }
    
    func testAddCustomTemplate() {
        let custom = PromptTemplate(
            title: "Jira Story Converter",
            description: "Convert transcript into user stories and acceptance criteria",
            systemPrompt: "As an agile product owner, rewrite into Jira story format.",
            category: .productivity,
            isBuiltIn: false
        )
        
        service.addCustomTemplate(custom)
        
        let templates = service.getTemplates()
        XCTAssertTrue(templates.contains(where: { $0.title == "Jira Story Converter" }))
    }
    
    func testFilterTemplatesByCategory() {
        let businessTemplates = service.getTemplates(for: .business)
        XCTAssertFalse(businessTemplates.isEmpty)
        for t in businessTemplates {
            XCTAssertEqual(t.category, .business)
        }
    }
    
    func testRemoveCustomTemplate() {
        let custom = PromptTemplate(
            title: "Temporary Template",
            description: "To be deleted",
            systemPrompt: "Test prompt",
            category: .custom,
            isBuiltIn: false
        )
        
        service.addCustomTemplate(custom)
        XCTAssertTrue(service.getTemplates().contains(where: { $0.id == custom.id }))
        
        service.removeCustomTemplate(id: custom.id)
        XCTAssertFalse(service.getTemplates().contains(where: { $0.id == custom.id }))
    }
}
