import Foundation

/// Protocol defining Grammar Correction Service contract.
public protocol GrammarCorrectionServiceProtocol {
    var isEnabled: Bool { get set }
    func correctGrammar(rawTranscript: String, config: LLMConfig) async throws -> String
}

/// Service handling optional AI-powered grammar correction for transcriptions.
public class GrammarCorrectionService: GrammarCorrectionServiceProtocol {
    public static let systemPrompt = "Correct grammar, punctuation, capitalization, spelling and formatting without changing the meaning, tone or wording unnecessarily. Do not summarize. Return only the corrected text."
    
    private let llmProviderService: LLMProviderServiceProtocol
    public var isEnabled: Bool
    
    public init(
        llmProviderService: LLMProviderServiceProtocol = LLMProviderService(),
        isEnabled: Bool = false
    ) {
        self.llmProviderService = llmProviderService
        self.isEnabled = isEnabled
    }
    
    public func correctGrammar(rawTranscript: String, config: LLMConfig) async throws -> String {
        // If grammar correction is disabled or text is empty, return raw transcript untouched
        guard isEnabled || config.isGrammarCorrectionEnabled else {
            return rawTranscript
        }
        
        let trimmed = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return rawTranscript
        }
        
        return try await llmProviderService.generateCompletion(
            prompt: trimmed,
            systemPrompt: GrammarCorrectionService.systemPrompt,
            config: config
        )
    }
}
