//
//  ProviderCapabilitiesTests.swift
//  EchoTests
//

import Testing
@testable import EchoCore

struct ProviderCapabilitiesTests {
    @Test("Capability flags match each provider's Android request behavior")
    func everyProviderCapabilities() {
        let expected: [ProviderId: ProviderCapabilities] = [
            .groq: openAICompatible,
            .openAI: openAICompatible,
            .openRouter: openAICompatible,
            .azure: azure,
            .custom: azure,
            .deepgram: languageOnly,
            .assemblyAI: languageOnly,
            .gemini: gemini,
        ]

        for id in ProviderId.allCases {
            #expect(ProviderRegistry.configuration(for: id).capabilities == expected[id])
        }
    }

    @Test("Custom URL and model capabilities are limited to Azure and Custom")
    func customConfigurationCapabilities() {
        for id in ProviderId.allCases {
            let capabilities = ProviderRegistry.configuration(for: id).capabilities
            if id == .azure || id == .custom {
                #expect(capabilities.supportsCustomBaseURL)
                #expect(capabilities.supportsCustomModel)
            } else {
                #expect(!capabilities.supportsCustomBaseURL)
                #expect(!capabilities.supportsCustomModel)
            }
        }
    }

    private var openAICompatible: ProviderCapabilities {
        ProviderCapabilities(
            supportsLanguageSelection: true,
            supportsPrompt: true,
            supportsVerboseJSON: true,
            supportsTemperature: true,
            supportsConnectionTest: true
        )
    }

    private var languageOnly: ProviderCapabilities {
        ProviderCapabilities(
            supportsLanguageSelection: true,
            supportsConnectionTest: true
        )
    }

    private var gemini: ProviderCapabilities {
        ProviderCapabilities(
            supportsLanguageSelection: true,
            supportsPrompt: true,
            supportsConnectionTest: true
        )
    }

    private var azure: ProviderCapabilities {
        ProviderCapabilities(
            supportsLanguageSelection: true,
            supportsPrompt: true,
            supportsVerboseJSON: true,
            supportsTemperature: true,
            supportsCustomBaseURL: true,
            supportsCustomModel: true,
            supportsConnectionTest: true
        )
    }
}
