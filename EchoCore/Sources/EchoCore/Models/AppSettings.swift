//
//  AppSettings.swift
//  Echo
//
//  Domain settings snapshot mirroring Android's domain.model.AppSettings.
//

import Foundation

public struct AppSettings: Equatable, Sendable {
    public var language: String
    public var model: String
    public var retentionDays: Int
    public var grammarEnabled: Bool
    public var theme: String
    public var autoStart: Bool
    /// Provider ID (lowercase name) to configured-state mapping.
    public var providerConfigured: [String: Bool]

    public init(
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
