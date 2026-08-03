//
//  ProviderFactoryTests.swift
//  EchoTests
//

import Foundation
import Testing
@testable import EchoCore

struct ProviderFactoryTests {
    @Test("Factory reports a missing API key")
    func missingAPIKey() async {
        await MainActor.run {
            let (settings, keychain) = makeDependencies()
            settings.selectedProvider = ProviderId.groq.rawValue
            let factory = ProviderFactory(keychainStore: keychain, providerSettings: settings)

            do {
                _ = try factory.getProvider()
                Issue.record("Expected missingAPIKey")
            } catch let error as ProviderError {
                #expect(error == .missingAPIKey(provider: .groq))
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    @Test("Factory reports a missing custom base URL")
    func missingBaseURL() async {
        await MainActor.run {
            let (settings, keychain) = makeDependencies()
            settings.selectedProvider = ProviderId.custom.rawValue
            settings.selectedModel = "custom-model"
            keychain.saveKey("secret", for: ProviderId.custom.rawValue)
            let factory = ProviderFactory(keychainStore: keychain, providerSettings: settings)

            do {
                _ = try factory.getProvider()
                Issue.record("Expected missingBaseURL")
            } catch let error as ProviderError {
                #expect(error == .missingBaseURL(provider: .custom))
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    @Test("Factory reports invalid configuration for an unsupported model")
    func invalidConfiguration() async {
        await MainActor.run {
            let (settings, keychain) = makeDependencies()
            settings.selectedProvider = ProviderId.openAI.rawValue
            settings.selectedModel = "not-a-registered-model"
            keychain.saveKey("secret", for: ProviderId.openAI.rawValue)
            let factory = ProviderFactory(keychainStore: keychain, providerSettings: settings)

            do {
                _ = try factory.getProvider()
                Issue.record("Expected invalidConfiguration")
            } catch let error as ProviderError {
                guard case let .invalidConfiguration(provider, _) = error else {
                    Issue.record("Unexpected ProviderError: \(error)")
                    return
                }
                #expect(provider == .openAI)
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    @Test("Factory reports unsupported persisted provider values")
    func unsupportedProvider() async {
        await MainActor.run {
            let (settings, keychain) = makeDependencies()
            settings.selectedProvider = "NOT_REGISTERED"
            let factory = ProviderFactory(keychainStore: keychain, providerSettings: settings)

            do {
                _ = try factory.getProvider()
                Issue.record("Expected unsupportedProvider")
            } catch let error as ProviderError {
                #expect(error == .unsupportedProvider(rawValue: "NOT_REGISTERED"))
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    @Test("Factory resolves a placeholder SpeechProvider for every provider")
    func resolvesEveryProvider() async {
        await MainActor.run {
            let (settings, keychain) = makeDependencies()

            for id in ProviderId.allCases {
                let config = ProviderRegistry.configuration(for: id)
                settings.selectedProvider = id.rawValue
                settings.selectedModel = config.capabilities.supportsCustomModel
                    ? "custom-model"
                    : config.defaultModel
                if config.capabilities.supportsCustomBaseURL {
                    settings.customBaseURL = "https://example.test/v1/"
                } else {
                    settings.customBaseURL = ""
                }
                keychain.saveKey("secret-\(id.rawValue)", for: id.rawValue)

                do {
                    let provider = try ProviderFactory(
                        keychainStore: keychain,
                        providerSettings: settings
                    ).getProvider()
                    #expect(provider.config.id == id)
                    // Phase 4: factory now resolves real SpeechProvider instances
                    #expect(!(provider is UnavailableSpeechProvider))
                } catch {
                    Issue.record("Unexpected error for \(id.rawValue): \(error)")
                }
            }
        }
    }

    @MainActor
    private func makeDependencies() -> (ProviderSettings, KeychainStore) {
        let suiteName = "EchoTests.ProviderFactory.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = ProviderSettings(userDefaults: defaults)
        let keychain = KeychainStore(
            service: "EchoTests.ProviderFactory.\(UUID().uuidString)",
            backend: InMemoryKeychainBackend()
        )
        return (settings, keychain)
    }
}
