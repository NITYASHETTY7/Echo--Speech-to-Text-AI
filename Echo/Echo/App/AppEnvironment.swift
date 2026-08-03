//
//  AppEnvironment.swift
//  Echo
//
//  SwiftUI dependency-injection wiring for app-wide services.
//  V3: AIService added to the environment.
//

import SwiftUI
import EchoCore
import os

// MARK: - Environment Keys

private struct KeychainStoreEnvironmentKey: EnvironmentKey {
    static let defaultValue: KeychainStore? = nil
}

private struct TranscriptionStoreEnvironmentKey: EnvironmentKey {
    static let defaultValue: TranscriptionStore? = nil
}

private struct AIServiceEnvironmentKey: EnvironmentKey {
    static let defaultValue: AIService? = nil
}

extension EnvironmentValues {
    var keychainStore: KeychainStore? {
        get { self[KeychainStoreEnvironmentKey.self] }
        set { self[KeychainStoreEnvironmentKey.self] = newValue }
    }

    var transcriptionStore: TranscriptionStore? {
        get { self[TranscriptionStoreEnvironmentKey.self] }
        set { self[TranscriptionStoreEnvironmentKey.self] = newValue }
    }

    var aiService: AIService? {
        get { self[AIServiceEnvironmentKey.self] }
        set { self[AIServiceEnvironmentKey.self] = newValue }
    }
}

// MARK: - AppEnvironment

enum AppEnvironment {
    static func bootstrap() {
        EchoLog.app.info("Echo starting up")
    }
}

// MARK: - View modifier

extension View {
    @MainActor
    func withAppEnvironment(
        preferences: Preferences,
        providerSettings: ProviderSettings,
        keychainStore: KeychainStore,
        transcriptionStore: TranscriptionStore,
        authViewModel: AuthViewModel,
        aiService: AIService
    ) -> some View {
        self
            .environment(preferences)
            .environment(providerSettings)
            .environment(\.keychainStore, keychainStore)
            .environment(\.transcriptionStore, transcriptionStore)
            .environment(authViewModel)
            .environment(\.aiService, aiService)
    }
}
