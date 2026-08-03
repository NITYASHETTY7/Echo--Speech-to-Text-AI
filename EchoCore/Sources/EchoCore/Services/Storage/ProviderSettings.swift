//
//  ProviderSettings.swift
//  Echo
//
//  UserDefaults-backed provider selection settings corresponding to Android's
//  speech.provider.ProviderSettings. Provider metadata is resolved from
//  ProviderRegistry so configuration is not duplicated.
//

import Foundation
import Observation

@MainActor
@Observable
public final class ProviderSettings {
    @ObservationIgnored private let defaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults
    }

    /// Currently selected provider. Android defaults to GROQ.
    public var selectedProvider: String {
        get { defaults.string(forKey: Keys.provider) ?? ProviderId.groq.rawValue }
        set { defaults.set(newValue, forKey: Keys.provider) }
    }

    /// Stored model, or the registry's default model for the selected provider.
    /// This matches ProviderSettings.selectedModel on Android.
    public var selectedModel: String {
        get {
            if let stored = defaults.string(forKey: Keys.model), !stored.isEmpty {
                return stored
            }
            return ProviderRegistry
                .configuration(forRawValue: selectedProvider)?
                .defaultModel ?? ""
        }
        set { defaults.set(newValue, forKey: Keys.model) }
    }

    /// User-supplied URL used for providers whose endpoint is configurable.
    public var customBaseURL: String {
        get { defaults.string(forKey: Keys.baseURL) ?? "" }
        set { defaults.set(newValue, forKey: Keys.baseURL) }
    }

    /// Effective endpoint using registry configuration and the user's URL for
    /// providers that advertise supportsCustomBaseURL.
    public func effectiveBaseURL() -> String {
        guard let config = ProviderRegistry.configuration(forRawValue: selectedProvider) else {
            return ""
        }
        return config.capabilities.supportsCustomBaseURL
            ? customBaseURL
            : config.defaultBaseURL
    }

    private enum Keys {
        static let provider = "selected_provider"
        static let model = "selected_model"
        static let baseURL = "custom_base_url"
    }
}
