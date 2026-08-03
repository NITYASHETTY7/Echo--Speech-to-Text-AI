//
//  ProviderConfig.swift
//  Echo
//
//  Static configuration for one speech provider. Credentials and user values
//  remain in KeychainStore and ProviderSettings.
//

import Foundation

struct ProviderConfig: Equatable, Sendable {
    let id: ProviderId
    let displayName: String
    let defaultBaseURL: String
    let supportedModels: [String]
    let defaultModel: String
    let authHeaderName: String
    let authHeaderValueFormat: String
    let capabilities: ProviderCapabilities

    init(
        id: ProviderId,
        displayName: String,
        defaultBaseURL: String,
        supportedModels: [String],
        defaultModel: String,
        authHeaderName: String,
        authHeaderValueFormat: String,
        capabilities: ProviderCapabilities
    ) {
        self.id = id
        self.displayName = displayName
        self.defaultBaseURL = defaultBaseURL
        self.supportedModels = supportedModels
        self.defaultModel = defaultModel
        self.authHeaderName = authHeaderName
        self.authHeaderValueFormat = authHeaderValueFormat
        self.capabilities = capabilities
    }

    // Android-parity aliases retained for provider code migrated later.
    var models: [String] { supportedModels }
    var defaultBaseUrl: String { defaultBaseURL }
    var authValueFormat: String { authHeaderValueFormat }
}
