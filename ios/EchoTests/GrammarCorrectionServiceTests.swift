import XCTest
@testable import Echo

final class GrammarCorrectionServiceTests: XCTestCase {
    
    class MockLLMProviderService: LLMProviderServiceProtocol {
        var lastPrompt: String?
        var lastSystemPrompt: String?
        var mockResponse: String = "This is corrected grammar."
        
        func generateCompletion(prompt: String, systemPrompt: String?, config: LLMConfig) async throws -> String {
            self.lastPrompt = prompt
            self.lastSystemPrompt = systemPrompt
            return mockResponse
        }
    }
    
    func testGrammarCorrectionDisabledReturnsRawText() async throws {
        let mockLLM = MockLLMProviderService()
        let service = GrammarCorrectionService(llmProviderService: mockLLM, isEnabled: false)
        let config = LLMConfig(isGrammarCorrectionEnabled: false)
        
        let rawText = "this is raw text with bad grammar"
        let result = try await service.correctGrammar(rawTranscript: rawText, config: config)
        
        XCTAssertEqual(result, rawText)
        XCTAssertNil(mockLLM.lastPrompt)
    }
    
    func testGrammarCorrectionEnabledExecutesLLMWithPrompt() async throws {
        let mockLLM = MockLLMProviderService()
        mockLLM.mockResponse = "This is raw text with correct grammar."
        let service = GrammarCorrectionService(llmProviderService: mockLLM, isEnabled: true)
        let config = LLMConfig(isGrammarCorrectionEnabled: true)
        
        let rawText = "this is raw text with bad grammar"
        let result = try await service.correctGrammar(rawTranscript: rawText, config: config)
        
        XCTAssertEqual(result, "This is raw text with correct grammar.")
        XCTAssertEqual(mockLLM.lastPrompt, rawText)
        XCTAssertEqual(mockLLM.lastSystemPrompt, GrammarCorrectionService.systemPrompt)
        XCTAssertTrue(mockLLM.lastSystemPrompt?.contains("Correct grammar, punctuation, capitalization, spelling") == true)
    }
    
    func testEmptyTranscriptReturnsEmptyWithoutError() async throws {
        let mockLLM = MockLLMProviderService()
        let service = GrammarCorrectionService(llmProviderService: mockLLM, isEnabled: true)
        let config = LLMConfig(isGrammarCorrectionEnabled: true)
        
        let result = try await service.correctGrammar(rawTranscript: "   ", config: config)
        XCTAssertEqual(result, "   ")
    }
}
