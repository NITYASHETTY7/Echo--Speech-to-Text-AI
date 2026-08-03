//
//  ProviderFactory.swift
//  EchoCore
//
//  Resolves the selected provider. V3: adds getLLMProvider() for chat/completions.
//  Uses the currently selected provider — never hardcodes a specific provider.
//

import Foundation

@MainActor
public final class ProviderFactory {
    private let keychainStore: KeychainStore
    private let providerSettings: ProviderSettings
    private let httpClient: HTTPClient

    public init(
        keychainStore: KeychainStore,
        providerSettings: ProviderSettings,
        httpClient: HTTPClient = HTTPClient()
    ) {
        self.keychainStore = keychainStore
        self.providerSettings = providerSettings
        self.httpClient = httpClient
    }

    // MARK: - Speech provider

    /// Returns a fully configured `SpeechProvider` for the current settings.
    public func getProvider() throws -> any SpeechProvider {
        let rawProvider = providerSettings.selectedProvider
        guard let config = ProviderRegistry.configuration(forRawValue: rawProvider) else {
            throw ProviderError.unsupportedProvider(rawValue: rawProvider)
        }
        guard keychainStore.isConfigured(for: config.id.rawValue) else {
            throw ProviderError.missingAPIKey(provider: config.id)
        }
        let baseURL = try validatedBaseURL(for: config)
        try validateModel(for: config)
        guard let apiKey = keychainStore.loadKey(for: config.id.rawValue) else {
            throw ProviderError.missingAPIKey(provider: config.id)
        }
        let effectiveConfig = config.capabilities.supportsCustomBaseURL
            ? config.withBaseURL(baseURL)
            : config
        return makeSpeechProvider(for: effectiveConfig, apiKey: apiKey)
    }

    // MARK: - LLM provider (V3)

    /// Returns a fully configured `LLMProvider` for the currently selected provider.
    /// Throws `ProviderError.unsupportedProvider` if the provider has no LLM capability.
    public func getLLMProvider() throws -> any LLMProvider {
        let rawProvider = providerSettings.selectedProvider
        guard let config = ProviderRegistry.configuration(forRawValue: rawProvider) else {
            throw ProviderError.unsupportedProvider(rawValue: rawProvider)
        }
        guard config.capabilities.supportsTextCompletion else {
            throw ProviderError.unsupportedProvider(rawValue: rawProvider)
        }
        guard keychainStore.isConfigured(for: config.id.rawValue) else {
            throw ProviderError.missingAPIKey(provider: config.id)
        }
        guard let apiKey = keychainStore.loadKey(for: config.id.rawValue) else {
            throw ProviderError.missingAPIKey(provider: config.id)
        }

        // Resolve effective chat base URL
        let chatURL: String
        if config.capabilities.supportsCustomBaseURL {
            let custom = providerSettings.customBaseURL
                .trimmingCharacters(in: .whitespacesAndNewlines)
            chatURL = custom.isEmpty ? (config.chatBaseURL ?? config.defaultBaseURL) : custom
        } else {
            chatURL = config.chatBaseURL ?? config.defaultBaseURL
        }

        return makeLLMProvider(for: config, chatBaseURL: chatURL, apiKey: apiKey)
    }

    /// Display name of the current provider (used by AIService for metadata).
    public var currentProviderDisplayName: String {
        ProviderRegistry.configuration(forRawValue: providerSettings.selectedProvider)?.displayName
            ?? providerSettings.selectedProvider
    }

    /// Default chat model for the current provider.
    public var currentDefaultChatModel: String {
        ProviderRegistry.configuration(forRawValue: providerSettings.selectedProvider)?
            .defaultChatModel ?? "default"
    }

    /// True when the selected provider supports text completion.
    public var currentProviderSupportsLLM: Bool {
        ProviderRegistry.configuration(forRawValue: providerSettings.selectedProvider)?
            .capabilities.supportsTextCompletion ?? false
    }

    public func isCurrentProviderConfigured() -> Bool {
        guard let provider = ProviderId(rawValue: providerSettings.selectedProvider) else {
            return false
        }
        return keychainStore.isConfigured(for: provider.rawValue)
    }

    // MARK: - Provider dispatch

    private func makeSpeechProvider(for config: ProviderConfig, apiKey: String) -> any SpeechProvider {
        switch config.id {
        case .groq, .openAI, .openRouter, .azure, .custom:
            return OpenAICompatibleProvider(config: config, apiKey: apiKey, httpClient: httpClient)
        case .deepgram:
            return DeepgramProvider(config: config, apiKey: apiKey, httpClient: httpClient)
        case .assemblyAI:
            return AssemblyAIProvider(config: config, apiKey: apiKey, httpClient: httpClient)
        case .gemini:
            return GeminiProvider(config: config, apiKey: apiKey, httpClient: httpClient)
        }
    }

    private func makeLLMProvider(for config: ProviderConfig, chatBaseURL: String, apiKey: String) -> any LLMProvider {
        switch config.id {
        case .gemini:
            return GeminiLLMProvider(
                apiKey: apiKey,
                defaultModel: config.defaultChatModel ?? "gemini-1.5-flash",
                baseURL: chatBaseURL,
                httpClient: httpClient
            )
        default:
            // All other LLM-capable providers use the OpenAI chat/completions format
            return OpenAICompatibleLLMProvider(
                id: config.id.rawValue,
                name: config.displayName,
                baseURL: chatBaseURL,
                defaultModel: config.defaultChatModel ?? "gpt-4o-mini",
                apiKey: apiKey,
                httpClient: httpClient
            )
        }
    }

    // MARK: - Validation

    private func validatedBaseURL(for config: ProviderConfig) throws -> String {
        let candidate: String
        if config.capabilities.supportsCustomBaseURL {
            candidate = providerSettings.customBaseURL
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
                ? (keychainStore.loadBaseURL(for: config.id.rawValue) ?? "")
                : providerSettings.customBaseURL
        } else {
            candidate = config.defaultBaseURL
        }
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if config.capabilities.supportsCustomBaseURL {
                throw ProviderError.missingBaseURL(provider: config.id)
            }
            throw ProviderError.invalidConfiguration(
                provider: config.id,
                reason: "The registered default Base URL is empty."
            )
        }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            throw ProviderError.invalidConfiguration(
                provider: config.id,
                reason: "Base URL must be a valid HTTP or HTTPS URL."
            )
        }
        return trimmed
    }

    private func validateModel(for config: ProviderConfig) throws {
        let model = providerSettings.selectedModel
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw ProviderError.invalidConfiguration(provider: config.id, reason: "A model is required.")
        }
        if !config.capabilities.supportsCustomModel,
           !config.supportedModels.isEmpty,
           !config.supportedModels.contains(model) {
            throw ProviderError.invalidConfiguration(
                provider: config.id,
                reason: "Model \(model) is not in the registered model list."
            )
        }
    }
}

// MARK: - ProviderConfig helper

private extension ProviderConfig {
    func withBaseURL(_ url: String) -> ProviderConfig {
        ProviderConfig(
            id: id, displayName: displayName, defaultBaseURL: url,
            supportedModels: supportedModels, defaultModel: defaultModel,
            authHeaderName: authHeaderName, authHeaderValueFormat: authHeaderValueFormat,
            capabilities: capabilities,
            chatBaseURL: chatBaseURL, defaultChatModel: defaultChatModel,
            supportedChatModels: supportedChatModels
        )
    }
}
