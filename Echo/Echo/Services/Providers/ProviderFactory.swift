//
//  ProviderFactory.swift
//  Echo
//
//  Resolves the selected provider after validating credentials, then
//  constructs the concrete SpeechProvider with the shared HTTPClient.
//

import Foundation

@MainActor
final class ProviderFactory {
    private let keychainStore: KeychainStore
    private let providerSettings: ProviderSettings
    private let httpClient: HTTPClient

    init(
        keychainStore: KeychainStore,
        providerSettings: ProviderSettings,
        httpClient: HTTPClient = HTTPClient()
    ) {
        self.keychainStore = keychainStore
        self.providerSettings = providerSettings
        self.httpClient = httpClient
    }

    /// Returns a fully configured `SpeechProvider` for the current settings.
    func getProvider() throws -> any SpeechProvider {
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

        // For Azure/Custom, patch the config with the resolved base URL so
        // the provider doesn't need to repeat the lookup.
        let effectiveConfig = config.capabilities.supportsCustomBaseURL
            ? config.withBaseURL(baseURL)
            : config

        return makeProvider(for: effectiveConfig, apiKey: apiKey)
    }

    /// Android-parity convenience check used by the transcription flow.
    func isCurrentProviderConfigured() -> Bool {
        guard let provider = ProviderId(rawValue: providerSettings.selectedProvider) else {
            return false
        }
        return keychainStore.isConfigured(for: provider.rawValue)
    }

    // MARK: - Provider dispatch

    private func makeProvider(for config: ProviderConfig, apiKey: String) -> any SpeechProvider {
        switch config.id {
        case .groq:
            return OpenAICompatibleProvider(config: config, apiKey: apiKey, httpClient: httpClient)
        case .openAI:
            return OpenAICompatibleProvider(config: config, apiKey: apiKey, httpClient: httpClient)
        case .openRouter:
            return OpenAICompatibleProvider(config: config, apiKey: apiKey, httpClient: httpClient)
        case .azure:
            return OpenAICompatibleProvider(config: config, apiKey: apiKey, httpClient: httpClient)
        case .custom:
            return OpenAICompatibleProvider(config: config, apiKey: apiKey, httpClient: httpClient)
        case .deepgram:
            return DeepgramProvider(config: config, apiKey: apiKey, httpClient: httpClient)
        case .assemblyAI:
            return AssemblyAIProvider(config: config, apiKey: apiKey, httpClient: httpClient)
        case .gemini:
            return GeminiProvider(config: config, apiKey: apiKey, httpClient: httpClient)
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
            throw ProviderError.invalidConfiguration(
                provider: config.id,
                reason: "A model is required."
            )
        }

        if !config.capabilities.supportsCustomModel,
           !config.supportedModels.contains(model) {
            throw ProviderError.invalidConfiguration(
                provider: config.id,
                reason: "Model \(model) is not supported by the registered configuration."
            )
        }
    }
}

// MARK: - ProviderConfig convenience

private extension ProviderConfig {
    func withBaseURL(_ url: String) -> ProviderConfig {
        ProviderConfig(
            id: id,
            displayName: displayName,
            defaultBaseURL: url,
            supportedModels: supportedModels,
            defaultModel: defaultModel,
            authHeaderName: authHeaderName,
            authHeaderValueFormat: authHeaderValueFormat,
            capabilities: capabilities
        )
    }
}
