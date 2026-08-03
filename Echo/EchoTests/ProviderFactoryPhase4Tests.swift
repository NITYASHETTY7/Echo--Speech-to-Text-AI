//
//  ProviderFactoryPhase4Tests.swift
//  EchoTests
//

import Foundation
import Testing
@testable import EchoCore

@Suite(.serialized)
struct ProviderFactoryPhase4Tests {

    @Test("Factory returns OpenAICompatibleProvider for Groq, OpenAI, OpenRouter, Azure, Custom")
    func openAICompatibleProviders() async throws {
        let openAICompatible: [ProviderId] = [.groq, .openAI, .openRouter]
        for id in openAICompatible {
            try await MainActor.run {
                let (settings, keychain) = makeDependencies()
                let config = ProviderRegistry.configuration(for: id)
                settings.selectedProvider = id.rawValue
                settings.selectedModel = config.defaultModel
                keychain.saveKey("secret", for: id.rawValue)

                let mockClient = HTTPClient.makeTestClient { _ in
                    .init(statusCode: 200, data: Data())
                }
                defer { MockURLProtocol.uninstall() }
                let factory = ProviderFactory(
                    keychainStore: keychain,
                    providerSettings: settings,
                    httpClient: mockClient
                )
                let provider = try factory.getProvider()
                #expect(provider is OpenAICompatibleProvider, "Expected OpenAICompatibleProvider for \(id.rawValue)")
            }
        }
    }

    @Test("Factory returns OpenAICompatibleProvider for Azure with user base URL")
    func azureProvider() async throws {
        try await MainActor.run {
            let (settings, keychain) = makeDependencies()
            settings.selectedProvider = ProviderId.azure.rawValue
            settings.selectedModel = "whisper-model"
            settings.customBaseURL = "https://my.openai.azure.com/openai/deployments/test/"
            keychain.saveKey("azure-key", for: ProviderId.azure.rawValue)

            let factory = ProviderFactory(
                keychainStore: keychain,
                providerSettings: settings,
                httpClient: HTTPClient()
            )
            let provider = try factory.getProvider()
            #expect(provider is OpenAICompatibleProvider)
        }
    }

    @Test("Factory returns DeepgramProvider for deepgram")
    func deepgramProvider() async throws {
        try await MainActor.run {
            let (settings, keychain) = makeDependencies()
            settings.selectedProvider = ProviderId.deepgram.rawValue
            settings.selectedModel = "nova-3"
            keychain.saveKey("dg-key", for: ProviderId.deepgram.rawValue)

            let factory = ProviderFactory(keychainStore: keychain, providerSettings: settings, httpClient: HTTPClient())
            let provider = try factory.getProvider()
            #expect(provider is DeepgramProvider)
        }
    }

    @Test("Factory returns AssemblyAIProvider for assemblyAI")
    func assemblyAIProvider() async throws {
        try await MainActor.run {
            let (settings, keychain) = makeDependencies()
            settings.selectedProvider = ProviderId.assemblyAI.rawValue
            settings.selectedModel = "default"
            keychain.saveKey("aai-key", for: ProviderId.assemblyAI.rawValue)

            let factory = ProviderFactory(keychainStore: keychain, providerSettings: settings, httpClient: HTTPClient())
            let provider = try factory.getProvider()
            #expect(provider is AssemblyAIProvider)
        }
    }

    @Test("Factory returns GeminiProvider for gemini")
    func geminiProvider() async throws {
        try await MainActor.run {
            let (settings, keychain) = makeDependencies()
            settings.selectedProvider = ProviderId.gemini.rawValue
            settings.selectedModel = "gemini-2.0-flash"
            keychain.saveKey("goog-key", for: ProviderId.gemini.rawValue)

            let factory = ProviderFactory(keychainStore: keychain, providerSettings: settings, httpClient: HTTPClient())
            let provider = try factory.getProvider()
            #expect(provider is GeminiProvider)
        }
    }

    @Test("Factory resolved provider config matches registry")
    func providerConfigMatchesRegistry() async throws {
        try await MainActor.run {
            let (settings, keychain) = makeDependencies()
            settings.selectedProvider = ProviderId.groq.rawValue
            settings.selectedModel = "whisper-large-v3-turbo"
            keychain.saveKey("sk", for: ProviderId.groq.rawValue)

            let factory = ProviderFactory(keychainStore: keychain, providerSettings: settings, httpClient: HTTPClient())
            let provider = try factory.getProvider()
            #expect(provider.config.id == .groq)
            #expect(provider.config.authHeaderName == "Authorization")
        }
    }

    @MainActor
    private func makeDependencies() -> (ProviderSettings, KeychainStore) {
        let suiteName = "EchoTests.FactoryPhase4.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = ProviderSettings(userDefaults: defaults)
        let keychain = KeychainStore(
            service: "EchoTests.FactoryPhase4.\(UUID().uuidString)",
            backend: InMemoryKeychainBackend()
        )
        return (settings, keychain)
    }
}
