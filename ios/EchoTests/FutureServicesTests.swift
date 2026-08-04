import XCTest
@testable import Echo

final class FutureServicesTests: XCTestCase {
    
    class MockLLMProviderService: LLMProviderServiceProtocol {
        var lastPrompt: String?
        var lastSystemPrompt: String?
        var mockResponse: String = "Mock output"
        
        func generateCompletion(prompt: String, systemPrompt: String?, config: LLMConfig) async throws -> String {
            self.lastPrompt = prompt
            self.lastSystemPrompt = systemPrompt
            return mockResponse
        }
    }
    
    func testTranslationServiceExtension() async throws {
        let mockLLM = MockLLMProviderService()
        mockLLM.mockResponse = "Bonjour le monde"
        let service = TranslationService(llmService: mockLLM)
        
        let result = try await service.translate(text: "Hello world", targetLanguage: "French", config: LLMConfig.defaultConfig)
        
        XCTAssertEqual(result, "Bonjour le monde")
        XCTAssertTrue(mockLLM.lastSystemPrompt?.contains("French") == true)
    }
    
    func testToneAdjustmentServiceExtension() async throws {
        let mockLLM = MockLLMProviderService()
        mockLLM.mockResponse = "Enthusiastic text output!"
        let service = ToneAdjustmentService(llmService: mockLLM)
        
        let result = try await service.adjustTone(text: "Regular text", targetTone: "Enthusiastic", config: LLMConfig.defaultConfig)
        
        XCTAssertEqual(result, "Enthusiastic text output!")
        XCTAssertTrue(mockLLM.lastSystemPrompt?.contains("Enthusiastic") == true)
    }
    
    func testSimplificationServiceExtension() async throws {
        let mockLLM = MockLLMProviderService()
        mockLLM.mockResponse = "Simple explanation."
        let service = SimplificationService(llmService: mockLLM)
        
        let result = try await service.simplifyLanguage(text: "Complex technical jargon", targetGradeLevel: "5th grade level", config: LLMConfig.defaultConfig)
        
        XCTAssertEqual(result, "Simple explanation.")
        XCTAssertTrue(mockLLM.lastSystemPrompt?.contains("5th grade level") == true)
    }
    
    func testDomainFormattingServiceExtension() async throws {
        let mockLLM = MockLLMProviderService()
        let service = DomainFormattingService(llmService: mockLLM)
        
        for domain in DomainFormattingType.allCases {
            mockLLM.mockResponse = "Formatted \(domain.rawValue) text"
            let result = try await service.formatDomainText(text: "Sample transcript", domain: domain, config: LLMConfig.defaultConfig)
            
            XCTAssertEqual(result, "Formatted \(domain.rawValue) text")
        }
    }
}
