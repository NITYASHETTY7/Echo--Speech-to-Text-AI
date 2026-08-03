//
//  ProviderRegistry.swift
//  Echo
//
//  Single source of truth for supported provider configuration.
//

import Foundation

enum ProviderRegistry {
    static let allConfigs: [ProviderConfig] = [
        ProviderConfig(
            id: .groq,
            displayName: "Groq",
            defaultBaseURL: "https://api.groq.com/openai/v1/",
            supportedModels: ["whisper-large-v3-turbo", "whisper-large-v3"],
            defaultModel: "whisper-large-v3-turbo",
            authHeaderName: "Authorization",
            authHeaderValueFormat: "Bearer %@",
            capabilities: .openAICompatible
        ),
        ProviderConfig(
            id: .openAI,
            displayName: "OpenAI",
            defaultBaseURL: "https://api.openai.com/v1/",
            supportedModels: ["whisper-1", "gpt-4o-transcribe", "gpt-4o-mini-transcribe"],
            defaultModel: "whisper-1",
            authHeaderName: "Authorization",
            authHeaderValueFormat: "Bearer %@",
            capabilities: .openAICompatible
        ),
        ProviderConfig(
            id: .openRouter,
            displayName: "OpenRouter",
            defaultBaseURL: "https://openrouter.ai/api/v1/",
            supportedModels: ["openai/whisper-large-v3", "openai/whisper"],
            defaultModel: "openai/whisper-large-v3",
            authHeaderName: "Authorization",
            authHeaderValueFormat: "Bearer %@",
            capabilities: .openAICompatible
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
        ),
        ProviderConfig(
            id: .gemini,
            displayName: "Google Gemini",
            defaultBaseURL: "https://generativelanguage.googleapis.com/",
            supportedModels: ["gemini-2.0-flash", "gemini-1.5-flash"],
            defaultModel: "gemini-2.0-flash",
            authHeaderName: "x-goog-api-key",
            authHeaderValueFormat: "%@",
            capabilities: .gemini
        ),
        ProviderConfig(
            id: .azure,
            displayName: "Azure OpenAI",
            defaultBaseURL: "",
            supportedModels: [],
            defaultModel: "",
            authHeaderName: "api-key",
            authHeaderValueFormat: "%@",
            capabilities: .azure
        ),
        ProviderConfig(
            id: .custom,
            displayName: "Custom OpenAI-Compatible",
            defaultBaseURL: "",
            supportedModels: [],
            defaultModel: "",
            authHeaderName: "Authorization",
            authHeaderValueFormat: "Bearer %@",
            capabilities: .custom
        ),
    ]

    static func configuration(for id: ProviderId) -> ProviderConfig {
        // Every ProviderId is registered in this phase. Keeping the guard makes
        // registry corruption a typed failure at the factory boundary.
        guard let config = allConfigs.first(where: { $0.id == id }) else {
            preconditionFailure("No configuration registered for \(id.rawValue)")
        }
        return config
    }

    static func configuration(forRawValue rawValue: String) -> ProviderConfig? {
        guard let id = ProviderId(rawValue: rawValue) else { return nil }
        return allConfigs.first { $0.id == id }
    }

    static let openAICompatibleCapabilities = ProviderCapabilities(
        supportsStreaming: false,
        supportsLanguageSelection: true,
        supportsPrompt: true,
        supportsVerboseJSON: true,
        supportsWordTimestamps: false,
        supportsTemperature: true,
        supportsCustomBaseURL: false,
        supportsCustomModel: false,
        supportsConnectionTest: true
    )

    static let deepgramCapabilities = ProviderCapabilities(
        supportsLanguageSelection: true,
        supportsConnectionTest: true
    )

    static let assemblyAICapabilities = ProviderCapabilities(
        supportsLanguageSelection: true,
        supportsConnectionTest: true
    )

    static let geminiCapabilities = ProviderCapabilities(
        supportsLanguageSelection: true,
        supportsPrompt: true,
        supportsConnectionTest: true
    )

    static let azureCapabilities = ProviderCapabilities(
        supportsLanguageSelection: true,
        supportsPrompt: true,
        supportsVerboseJSON: true,
        supportsTemperature: true,
        supportsCustomBaseURL: true,
        supportsCustomModel: true,
        supportsConnectionTest: true
    )

    static let customCapabilities = azureCapabilities
}

private extension ProviderCapabilities {
    static let openAICompatible = ProviderRegistry.openAICompatibleCapabilities
    static let deepgram = ProviderRegistry.deepgramCapabilities
    static let assemblyAI = ProviderRegistry.assemblyAICapabilities
    static let gemini = ProviderRegistry.geminiCapabilities
    static let azure = ProviderRegistry.azureCapabilities
    static let custom = ProviderRegistry.customCapabilities
}
