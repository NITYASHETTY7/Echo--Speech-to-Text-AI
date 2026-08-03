//
//  ProviderRegistryTests.swift
//  EchoTests
//

import Testing
@testable import EchoCore

struct ProviderRegistryTests {
    @Test("Registry contains exactly all Android-supported providers")
    func containsAllProviders() {
        let registered = Set(ProviderRegistry.allConfigs.map(\.id))
        #expect(registered == Set(ProviderId.allCases))
        #expect(ProviderRegistry.allConfigs.count == 8)
    }

    @Test("Every configuration has valid identity, model, and authentication metadata")
    func configurationIntegrity() {
        for config in ProviderRegistry.allConfigs {
            #expect(config.id.displayName == config.displayName)
            #expect(!config.displayName.isEmpty)
            #expect(!config.authHeaderName.isEmpty)
            #expect(config.authHeaderValueFormat.contains("%@"))

            if config.capabilities.supportsCustomBaseURL {
                #expect(config.defaultBaseURL.isEmpty)
            } else {
                #expect(!config.defaultBaseURL.isEmpty)
            }

            if config.capabilities.supportsCustomModel {
                #expect(config.supportedModels.isEmpty)
                #expect(config.defaultModel.isEmpty)
            } else {
                #expect(!config.supportedModels.isEmpty)
                #expect(config.supportedModels.contains(config.defaultModel))
            }
        }
    }

    @Test("Default models match Android ProviderRegistry")
    func defaultModelsMatchAndroid() {
        let expected: [ProviderId: String] = [
            .groq: "whisper-large-v3-turbo",
            .openAI: "whisper-1",
            .openRouter: "openai/whisper-large-v3",
            .deepgram: "nova-3",
            .assemblyAI: "default",
            .gemini: "gemini-2.0-flash",
            .azure: "",
            .custom: "",
        ]

        for id in ProviderId.allCases {
            #expect(ProviderRegistry.configuration(for: id).defaultModel == expected[id])
        }
    }

    @Test("Authentication metadata matches Android ProviderRegistry")
    func authenticationMetadataMatchesAndroid() {
        let expected: [ProviderId: (String, String)] = [
            .groq: ("Authorization", "Bearer %@"),
            .openAI: ("Authorization", "Bearer %@"),
            .openRouter: ("Authorization", "Bearer %@"),
            .deepgram: ("Authorization", "Token %@"),
            .assemblyAI: ("Authorization", "%@"),
            .gemini: ("x-goog-api-key", "%@"),
            .azure: ("api-key", "%@"),
            .custom: ("Authorization", "Bearer %@"),
        ]

        for id in ProviderId.allCases {
            let config = ProviderRegistry.configuration(for: id)
            #expect(config.authHeaderName == expected[id]?.0)
            #expect(config.authHeaderValueFormat == expected[id]?.1)
        }
    }

    @Test("Raw provider values support persisted ProviderSettings values")
    func rawValueLookup() {
        for id in ProviderId.allCases {
            #expect(ProviderRegistry.configuration(forRawValue: id.rawValue)?.id == id)
        }
        #expect(ProviderRegistry.configuration(forRawValue: "UNKNOWN") == nil)
    }
}
