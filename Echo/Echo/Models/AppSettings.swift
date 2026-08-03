//
//  AppSettings.swift
//  Echo
//
//  Domain settings snapshot mirroring Android's domain.model.AppSettings.
//

import Foundation

struct AppSettings: Equatable, Sendable {
    var language: String
    var model: String
    var retentionDays: Int
    var grammarEnabled: Bool
    var theme: String
    var autoStart: Bool
    /// Provider ID (lowercase name) to configured-state mapping.
    var providerConfigured: [String: Bool]

    init(
        language: String = AppConfig.Defaults.language,
        model: String = AppConfig.Defaults.model,
        retentionDays: Int = AppConfig.Defaults.retentionDays,
        grammarEnabled: Bool = AppConfig.Defaults.grammarEnabled,
        theme: String = AppConfig.Defaults.theme,
        autoStart: Bool = false,
        providerConfigured: [String: Bool] = [:]
    ) {
        self.language = language
        self.model = model
        self.retentionDays = retentionDays
        self.grammarEnabled = grammarEnabled
        self.theme = theme
        self.autoStart = autoStart
        self.providerConfigured = providerConfigured
    }
}
