import Foundation

/// Supported LLM providers.
public enum LLMProvider: String, Codable, CaseIterable, Identifiable {
    case openAI = "OpenAI"
    case gemini = "Gemini"
    case groq = "Groq"
    case azure = "Azure OpenAI"
    case openRouter = "OpenRouter"
    case custom = "Custom Endpoint"
    
    public var id: String { rawValue }
    
    public var defaultModel: String {
        switch self {
        case .openAI: return "gpt-4o-mini"
        case .gemini: return "gemini-1.5-flash"
        case .groq: return "llama-3.3-70b-versatile"
        case .azure: return "gpt-4o"
        case .openRouter: return "auto"
        case .custom: return "default"
        }
    }
}

/// Configuration settings for AI features and LLM integrations.
public struct LLMConfig: Codable, Equatable {
    public var provider: LLMProvider
    public var apiKey: String
    public var modelName: String
    public var customEndpoint: String?
    public var isGrammarCorrectionEnabled: Bool
    
    public init(
        provider: LLMProvider = .openAI,
        apiKey: String = "",
        modelName: String? = nil,
        customEndpoint: String? = nil,
        isGrammarCorrectionEnabled: Bool = false
    ) {
        self.provider = provider
        self.apiKey = apiKey
        self.modelName = modelName ?? provider.defaultModel
        self.customEndpoint = customEndpoint
        self.isGrammarCorrectionEnabled = isGrammarCorrectionEnabled
    }
    
    public static var defaultConfig: LLMConfig {
        LLMConfig()
    }
}
