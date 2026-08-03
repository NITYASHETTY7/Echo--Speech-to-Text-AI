//
//  KeychainStoreTests.swift
//  EchoTests
//

import Foundation
import Testing
@testable import EchoCore

struct KeychainStoreTests {
    private func makeStore() -> KeychainStore {
        KeychainStore(
            service: "test.\(UUID().uuidString)",
            accessGroup: "test-group",
            backend: InMemoryKeychainBackend()
        )
    }

    @Test("Keychain keys round-trip per provider")
    func savesLoadsAndClearsKey() {
        let store = makeStore()

        #expect(store.loadKey(for: "GROQ") == nil)
        #expect(!store.isConfigured(for: "GROQ"))

        store.saveKey("secret-key", for: "GROQ")
        #expect(store.loadKey(for: "GROQ") == "secret-key")
        #expect(store.isConfigured(for: "GROQ"))
        #expect(store.loadKey(for: "OPENAI") == nil)

        store.clearKey(for: "GROQ")
        #expect(store.loadKey(for: "GROQ") == nil)
        #expect(!store.isConfigured(for: "GROQ"))
    }

    @Test("Blank keys remove the stored key")
    func blankKeyClearsExistingValue() {
        let store = makeStore()
        store.saveKey("secret-key", for: "GROQ")

        store.saveKey("   ", for: "GROQ")

        #expect(store.loadKey(for: "GROQ") == nil)
    }

    @Test("Base URLs are stored independently from API keys")
    func baseURLRoundTripAndBlankRemoval() {
        let store = makeStore()
        store.saveKey("secret-key", for: "CUSTOM")
        store.saveBaseURL("https://example.test/v1/", for: "CUSTOM")

        #expect(store.loadKey(for: "CUSTOM") == "secret-key")
        #expect(store.loadBaseURL(for: "CUSTOM") == "https://example.test/v1/")

        store.saveBaseURL("", for: "CUSTOM")
        #expect(store.loadBaseURL(for: "CUSTOM") == nil)
        #expect(store.loadKey(for: "CUSTOM") == "secret-key")
    }
}
