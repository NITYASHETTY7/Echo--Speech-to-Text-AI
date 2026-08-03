//
//  ProviderRegistry.swift
//  EchoCore
//
//  Single source of truth for all provider configurations.
//  V3: LLM chat models and chatBaseURL added to all providers that support text completion.
//

import Foundation

public enum ProviderRegistry {

    // MARK: - All provider configurations

    public static let allConfigs: [ProviderConfig] = [
        ProviderConfig(
            id: .groq,
            displayName: "Groq",
            defaultBaseURL: "https://api.groq.com/openai/v1/",
            supportedModels: ["whisper-large-v3-turbo", "whisper-large-v3"],
            defaultModel: "whisper-large-v3-turbo",
            authHeaderName: "Authorization",
            authHeaderValueFormat: "Bearer %@",
            capabilities: .openAICompatibleLLM,
            chatBaseURL: "https://api.groq.com/openai/v1/",
            defaultChatModel: "llama-3.3-70b-versatile",
            supportedChatModels: [
                "llama-3.3-70b-versatile",
                "llama-3.1-70b-versatile",
                "llama-3.1-8b-instant",
                "mixtral-8x7b-32768",
            ]
        ),
        ProviderConfig(
            id: .openAI,
            displayName: "OpenAI",
            defaultBaseURL: "https://api.openai.com/v1/",
            supportedModels: ["whisper-1", "gpt-4o-transcribe", "gpt-4o-mini-transcribe"],
            defaultModel: "whisper-1",
            authHeaderName: "Authorization",
            authHeaderValueFormat: "Bearer %@",
            capabilities: .openAICompatibleLLM,
            chatBaseURL: "https://api.openai.com/v1/",
            defaultChatModel: "gpt-4o-mini",
            supportedChatModels: ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-3.5-turbo"]
        ),
        ProviderConfig(
            id: .openRouter,
            displayName: "OpenRouter",
            defaultBaseURL: "https://openrouter.ai/api/v1/",
            supportedModels: ["openai/whisper-large-v3", "openai/whisper"],
            defaultModel: "openai/whisper-large-v3",
            authHeaderName: "Authorization",
            authHeaderValueFormat: "Bearer %@",
            capabilities: .openAICompatibleLLM,
            chatBaseURL: "https://openrouter.ai/api/v1/",
            defaultChatModel: "openai/gpt-4o-mini",
            supportedChatModels: [
                "openai/gpt-4o", "openai/gpt-4o-mini",
                "google/gemini-pro", "anthropic/claude-3-haiku",
                "meta-llama/llama-3-70b-instruct",
            ]
        ),
        ProviderConfig(
            id: .deepgram,
            displayName: "Deepgram",
            defaultBaseURL: "https://api.deepgram.com/",
            supportedModels: ["nova-3", "nova-2"],
            defaultModel: "nova-3",
            authHeaderName: "Authorization",
            authHeaderValueFormat: "Token %@",
            capabilities: .deepgram
            // Deepgram has no LLM chat capability
        ),
        ProviderConfig(
            id: .assemblyAI,
            displayName: "AssemblyAI",
            defaultBaseURL: "https://api.assemblyai.com/",
            supportedModels: ["default"],
            defaultModel: "default",
            authHeaderName: "Authorization",
            authHeaderValueFormat: "%@",
            capabilities: .assemblyAI
            // AssemblyAI has no LLM chat capability
        ),
        ProviderConfig(
            id: .gemini,
            displayName: "Google Gemini",
            defaultBaseURL: "https://generativelanguage.googleapis.com/",
            supportedModels: ["gemini-2.0-flash", "gemini-1.5-flash"],
            defaultModel: "gemini-2.0-flash",
            authHeaderName: "x-goog-api-key",
            authHeaderValueFormat: "%@",
            capabilities: .geminiLLM,
            chatBaseURL: "https://generativelanguage.googleapis.com/",
            defaultChatModel: "gemini-1.5-flash",
            supportedChatModels: ["gemini-1.5-pro", "gemini-1.5-flash", "gemini-2.0-flash"]
        ),
        ProviderConfig(
            id: .azure,
            displayName: "Azure OpenAI",
            defaultBaseURL: "",
            supportedModels: [],
            defaultModel: "",
            authHeaderName: "api-key",
            authHeaderValueFormat: "%@",
            capabilities: .azure,
            chatBaseURL: nil,          // user-configurable, same as speech base URL
            defaultChatModel: nil,
            supportedChatModels: []
        ),
        ProviderConfig(
            id: .custom,
            displayName: "Custom OpenAI-Compatible",
            defaultBaseURL: "",
            supportedModels: [],
            defaultModel: "",
            authHeaderName: "Authorization",
            authHeaderValueFormat: "Bearer %@",
            capabilities: .custom,
            chatBaseURL: nil,
            defaultChatModel: nil,
            supportedChatModels: []
        ),
    ]

    // MARK: - Lookups

    public static func configuration(for id: ProviderId) -> ProviderConfig {
        guard let config = allConfigs.first(where: { $0.id == id }) else {
            preconditionFailure("No configuration registered for \(id.rawValue)")
        }
        return config
    }

    public static func configuration(forRawValue rawValue: String) -> ProviderConfig? {
        guard let id = ProviderId(rawValue: rawValue) else { return nil }
        return allConfigs.first { $0.id == id }
    }

    // MARK: - Capability presets

    // Speech-only (no LLM)
    public static let openAICompatibleCapabilities = ProviderCapabilities(
        supportsStreaming: false,
        supportsLanguageSelection: true,
        supportsPrompt: true,
        supportsVerboseJSON: true,
        supportsWordTimestamps: false,
        supportsTemperature: true,
        supportsCustomBaseURL: false,
        supportsCustomModel: false,
        supportsConnectionTest: true,
        supportsTextCompletion: false,
        supportsSystemPrompt: false
    )

    // Speech + LLM (Groq, OpenAI, OpenRouter)
    public static let openAICompatibleLLMCapabilities = ProviderCapabilities(
        supportsStreaming: false,
        supportsLanguageSelection: true,
        supportsPrompt: true,
        supportsVerboseJSON: true,
        supportsWordTimestamps: false,
        supportsTemperature: true,
        supportsCustomBaseURL: false,
        supportsCustomModel: false,
        supportsConnectionTest: true,
        supportsTextCompletion: true,
        supportsSystemPrompt: true
    )

    public static let deepgramCapabilities = ProviderCapabilities(
        supportsLanguageSelection: true,
        supportsConnectionTest: true
    )

    public static let assemblyAICapabilities = ProviderCapabilities(
        supportsLanguageSelection: true,
        supportsConnectionTest: true
    )

    // Gemini speech only
    public static let geminiCapabilities = ProviderCapabilities(
        supportsLanguageSelection: true,
        supportsPrompt: true,
        supportsConnectionTest: true
    )

    // Gemini with LLM
    public static let geminiLLMCapabilities = ProviderCapabilities(
        supportsLanguageSelection: true,
        supportsPrompt: true,
        supportsConnectionTest: true,
        supportsTextCompletion: true,
        supportsSystemPrompt: true
    )

    public static let azureCapabilities = ProviderCapabilities(
        supportsLanguageSelection: true,
        supportsPrompt: true,
        supportsVerboseJSON: true,
        supportsTemperature: true,
        supportsCustomBaseURL: true,
        supportsCustomModel: true,
        supportsConnectionTest: true,
        supportsTextCompletion: true,
        supportsSystemPrompt: true
    )

    public static let customCapabilities = azureCapabilities
}

// MARK: - Convenience short-hands used inside ProviderConfig initialisers

private extension ProviderCapabilities {
    static let openAICompatible    = ProviderRegistry.openAICompatibleCapabilities
    static let openAICompatibleLLM = ProviderRegistry.openAICompatibleLLMCapabilities
    static let deepgram            = ProviderRegistry.deepgramCapabilities
    static let assemblyAI          = ProviderRegistry.assemblyAICapabilities
    static let gemini              = ProviderRegistry.geminiCapabilities
    static let geminiLLM           = ProviderRegistry.geminiLLMCapabilities
    static let azure               = ProviderRegistry.azureCapabilities
    static let custom              = ProviderRegistry.customCapabilities
}
