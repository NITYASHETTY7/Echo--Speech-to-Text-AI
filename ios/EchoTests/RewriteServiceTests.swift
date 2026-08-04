import XCTest
@testable import Echo

final class RewriteServiceTests: XCTestCase {
    
    class MockLLMProviderService: LLMProviderServiceProtocol {
        var lastPrompt: String?
        var lastSystemPrompt: String?
        var mockResponse: String = "Rewritten text output"
        
        func generateCompletion(prompt: String, systemPrompt: String?, config: LLMConfig) async throws -> String {
            self.lastPrompt = prompt
            self.lastSystemPrompt = systemPrompt
            return mockResponse
        }
    }
    
    func testPresetRewriteAllTypes() async throws {
        let mockLLM = MockLLMProviderService()
        let service = RewriteService(llmProviderService: mockLLM)
        let config = LLMConfig.defaultConfig
        let rawText = "We discussed the budget and deadline for the project."
        
        for preset in VersionType.PresetType.allCases {
            mockLLM.mockResponse = "Mock output for \(preset.rawValue)"
            let result = try await service.rewrite(transcript: rawText, preset: preset, config: config)
            
            XCTAssertEqual(result.originalText, rawText)
            XCTAssertEqual(result.rewrittenText, "Mock output for \(preset.rawValue)")
            XCTAssertEqual(result.versionCreated.type, .preset(preset))
            XCTAssertEqual(result.versionCreated.title, preset.rawValue)
        }
    }
    
    func testCustomPromptRewrite() async throws {
        let mockLLM = MockLLMProviderService()
        mockLLM.mockResponse = "Estimado equipo, adjunto los detalles."
        let service = RewriteService(llmProviderService: mockLLM)
        let config = LLMConfig.defaultConfig
        
        let customPrompt = "Translate to Spanish and make it polite."
        let rawText = "Here are the project details."
        
        let result = try await service.rewriteCustom(transcript: rawText, customPrompt: customPrompt, config: config)
        
        XCTAssertEqual(result.rewrittenText, "Estimado equipo, adjunto los details.")
        XCTAssertEqual(result.versionCreated.type, .custom(prompt: customPrompt))
        XCTAssertTrue(mockLLM.lastSystemPrompt?.contains(customPrompt) == true)
    }
    
    func testRewriteWithTemplate() async throws {
        let mockLLM = MockLLMProviderService()
        mockLLM.mockResponse = "Professional summary text."
        let service = RewriteService(llmProviderService: mockLLM)
        let config = LLMConfig.defaultConfig
        
        let template = PromptTemplate(
            title: "Executive Summary",
            description: "High level summary",
            systemPrompt: "Summarize for executive board",
            category: .summary
        )
        
        let result = try await service.rewriteWithTemplate(transcript: "Detailed technical discussion", template: template, config: config)
        
        XCTAssertEqual(result.rewrittenText, "Professional summary text.")
        XCTAssertEqual(result.versionCreated.title, "Executive Summary")
    }
}
