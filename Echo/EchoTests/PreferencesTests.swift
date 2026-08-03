//
//  PreferencesTests.swift
//  EchoTests
//
//  Preferences is @MainActor-isolated. Tests are async with MainActor.run
//  for the same reason as TranscriptionStoreTests — see that file.
//

import Foundation
import Testing
@testable import EchoCore

struct PreferencesTests {

    @Test("Preferences preserve Android defaults")
    func defaultsMatchAndroid() async {
        await MainActor.run {
            let suiteName = "EchoTests.Preferences.\(UUID().uuidString)"
            let ud = UserDefaults(suiteName: suiteName)!
            ud.removePersistentDomain(forName: suiteName)
            let prefs = Preferences(userDefaults: ud)

            #expect(prefs.language == "en")
            #expect(prefs.model == "whisper-large-v3-turbo")
            #expect(prefs.retention == 30)
            #expect(prefs.grammar)
            #expect(prefs.theme == "system")
            #expect(!prefs.autoStart)
            #expect(prefs.floatingPillX == Int.min)
            #expect(prefs.floatingPillY == Int.min)
        }
    }

    @Test("Preferences persist every Android setting")
    func valuesPersist() async {
        await MainActor.run {
            let suiteName = "EchoTests.Preferences.Shared.\(UUID().uuidString)"
            let ud = UserDefaults(suiteName: suiteName)!
            ud.removePersistentDomain(forName: suiteName)

            let first = Preferences(userDefaults: ud)
            first.language = "fr"
            first.model = "custom-model"
            first.retention = 7
            first.grammar = false
            first.theme = "dark"
            first.autoStart = true
            first.floatingPillX = 42
            first.floatingPillY = 84

            let second = Preferences(userDefaults: ud)
            #expect(second.language == "fr")
            #expect(second.model == "custom-model")
            #expect(second.retention == 7)
            #expect(!second.grammar)
            #expect(second.theme == "dark")
            #expect(second.autoStart)
            #expect(second.floatingPillX == 42)
            #expect(second.floatingPillY == 84)
        }
    }
}
