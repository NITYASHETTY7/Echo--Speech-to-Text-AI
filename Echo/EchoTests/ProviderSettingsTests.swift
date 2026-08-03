//
//  ProviderSettingsTests.swift
//  EchoTests
//
//  ProviderSettings is @MainActor-isolated. Tests are async with MainActor.run
//  for the same reason as TranscriptionStoreTests — see that file.
//

import Foundation
import Testing
@testable import EchoCore

struct ProviderSettingsTests {

    @Test("ProviderSettings preserve the Android GROQ defaults")
    func defaultsMatchAndroid() async {
        await MainActor.run {
            let suiteName = "EchoTests.ProviderSettings.\(UUID().uuidString)"
            let ud = UserDefaults(suiteName: suiteName)!
            ud.removePersistentDomain(forName: suiteName)
            let settings = ProviderSettings(userDefaults: ud)

            #expect(settings.selectedProvider == "GROQ")
            #expect(settings.selectedModel == "whisper-large-v3-turbo")
            #expect(settings.customBaseURL.isEmpty)
            #expect(settings.effectiveBaseURL() == "https://api.groq.com/openai/v1/")
        }
    }

    @Test("Selected model falls back to the active provider's first model")
    func modelFallbackFollowsProvider() async {
        await MainActor.run {
            let suiteName = "EchoTests.ProviderSettings.\(UUID().uuidString)"
            let ud = UserDefaults(suiteName: suiteName)!
            ud.removePersistentDomain(forName: suiteName)
            let settings = ProviderSettings(userDefaults: ud)

            settings.selectedProvider = "OPENAI"
            #expect(settings.selectedModel == "whisper-1")

            settings.selectedModel = "gpt-4o-transcribe"
            #expect(settings.selectedModel == "gpt-4o-transcribe")
        }
    }

    @Test("Azure and Custom use the user-supplied base URL")
    func customBaseURLBehavior() async {
        await MainActor.run {
            let suiteName = "EchoTests.ProviderSettings.\(UUID().uuidString)"
            let ud = UserDefaults(suiteName: suiteName)!
            ud.removePersistentDomain(forName: suiteName)
            let settings = ProviderSettings(userDefaults: ud)

            settings.selectedProvider = "CUSTOM"
            settings.customBaseURL = "https://localhost/v1/"
            #expect(settings.effectiveBaseURL() == "https://localhost/v1/")
            #expect(settings.selectedModel.isEmpty)
        }
    }

    @Test("ProviderSettings values persist through UserDefaults")
    func valuesPersist() async {
        await MainActor.run {
            let suiteName = "EchoTests.ProviderSettings.Shared.\(UUID().uuidString)"
            let ud = UserDefaults(suiteName: suiteName)!
            ud.removePersistentDomain(forName: suiteName)

            let first = ProviderSettings(userDefaults: ud)
            first.selectedProvider = "DEEPGRAM"
            first.selectedModel = "nova-2"
            first.customBaseURL = "https://example.test/"

            let second = ProviderSettings(userDefaults: ud)
            #expect(second.selectedProvider == "DEEPGRAM")
            #expect(second.selectedModel == "nova-2")
            #expect(second.customBaseURL == "https://example.test/")
        }
    }
}
