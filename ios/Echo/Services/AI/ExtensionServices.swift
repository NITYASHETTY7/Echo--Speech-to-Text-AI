import Foundation

// MARK: - Feature 7: Future-Friendly Service Protocols & Pluggable Implementations

/// Protocol for Translation feature extension.
public protocol TranslationServiceProtocol {
    func translate(text: String, targetLanguage: String, config: LLMConfig) async throws -> String
}

/// Protocol for Tone Adjustment feature extension.
public protocol ToneAdjustmentServiceProtocol {
    func adjustTone(text: String, targetTone: String, config: LLMConfig) async throws -> String
}

/// Protocol for Language Simplification feature extension.
public protocol SimplificationServiceProtocol {
    func simplifyLanguage(text: String, targetGradeLevel: String, config: LLMConfig) async throws -> String
}

/// Domain formatting options for vertical-specific formatting.
public enum DomainFormattingType: String, Codable, CaseIterable, Identifiable {
    case medical = "Medical Formatting"
    case legal = "Legal Formatting"
    case codeDocumentation = "Code Documentation"
    
    public var id: String { rawValue }
}

/// Protocol for Domain Formatting feature extensions (Medical, Legal, Code Documentation).
public protocol DomainFormattingServiceProtocol {
    func formatDomainText(text: String, domain: DomainFormattingType, config: LLMConfig) async throws -> String
}

// MARK: - Extension Implementations

public class TranslationService: TranslationServiceProtocol {
    private let llmService: LLMProviderServiceProtocol
    
    public init(llmService: LLMProviderServiceProtocol = LLMProviderService()) {
        self.llmService = llmService
    }
    
    public func translate(text: String, targetLanguage: String, config: LLMConfig) async throws -> String {
        let systemPrompt = "Translate the following transcript accurately into \(targetLanguage). Do not alter facts or context."
        return try await llmService.generateCompletion(prompt: text, systemPrompt: systemPrompt, config: config)
    }
}

public class ToneAdjustmentService: ToneAdjustmentServiceProtocol {
    private let llmService: LLMProviderServiceProtocol
    
    public init(llmService: LLMProviderServiceProtocol = LLMProviderService()) {
        self.llmService = llmService
    }
    
    public func adjustTone(text: String, targetTone: String, config: LLMConfig) async throws -> String {
        let systemPrompt = "Adjust the tone of the following transcript to be \(targetTone). Maintain original content and meaning."
        return try await llmService.generateCompletion(prompt: text, systemPrompt: systemPrompt, config: config)
    }
}

public class SimplificationService: SimplificationServiceProtocol {
    private let llmService: LLMProviderServiceProtocol
    
    public init(llmService: LLMProviderServiceProtocol = LLMProviderService()) {
        self.llmService = llmService
    }
    
    public func simplifyLanguage(text: String, targetGradeLevel: String = "Plain English", config: LLMConfig) async throws -> String {
        let systemPrompt = "Rewrite the transcript using \(targetGradeLevel) language. Explain complex terms simply and keep sentences short."
        return try await llmService.generateCompletion(prompt: text, systemPrompt: systemPrompt, config: config)
    }
}

public class DomainFormattingService: DomainFormattingServiceProtocol {
    private let llmService: LLMProviderServiceProtocol
    
    public init(llmService: LLMProviderServiceProtocol = LLMProviderService()) {
        self.llmService = llmService
    }
    
    public func formatDomainText(text: String, domain: DomainFormattingType, config: LLMConfig) async throws -> String {
        let systemPrompt: String
        switch domain {
        case .medical:
            systemPrompt = "Format this transcript into standard SOAP medical notes format (Subjective, Objective, Assessment, Plan)."
        case .legal:
            systemPrompt = "Format this transcript using formal legal case note structure with facts, issues, reasoning, and conclusions."
        case .codeDocumentation:
            systemPrompt = "Convert this technical transcript into clean markdown documentation with API specs, code blocks, and descriptions."
        }
        
        return try await llmService.generateCompletion(prompt: text, systemPrompt: systemPrompt, config: config)
    }
}
