//
//  ProviderConfig.swift
//  EchoCore
//
//  Static configuration for one provider.
//  V3 additions: chatBaseURL, defaultChatModel, supportedChatModels.
//

import Foundation

public struct ProviderConfig: Equatable, Sendable {
    // ── Core ──────────────────────────────────────────────────────────────────
    public let id: ProviderId
    public let displayName: String
    public let defaultBaseURL: String
    public let supportedModels: [String]      // speech models
    public let defaultModel: String           // default speech model
    public let authHeaderName: String
    public let authHeaderValueFormat: String
    public let capabilities: ProviderCapabilities

    // ── LLM / chat ────────────────────────────────────────────────────────────
    /// Base URL for chat/completions endpoint. Nil for speech-only providers.
    public let chatBaseURL: String?
    /// Default LLM model for grammar/rewrite/translation.
    public let defaultChatModel: String?
    /// All LLM models this provider supports for text completion.
    public let supportedChatModels: [String]

    public init(
        id: ProviderId,
        displayName: String,
        defaultBaseURL: String,
        supportedModels: [String],
        defaultModel: String,
        authHeaderName: String,
        authHeaderValueFormat: String,
        capabilities: ProviderCapabilities,
        chatBaseURL: String? = nil,
        defaultChatModel: String? = nil,
        supportedChatModels: [String] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.defaultBaseURL = defaultBaseURL
        self.supportedModels = supportedModels
        self.defaultModel = defaultModel
        self.authHeaderName = authHeaderName
        self.authHeaderValueFormat = authHeaderValueFormat
        self.capabilities = capabilities
        self.chatBaseURL = chatBaseURL
        self.defaultChatModel = defaultChatModel
        self.supportedChatModels = supportedChatModels
    }

    // Backward-compat aliases
    public var models: [String] { supportedModels }
    public var defaultBaseUrl: String { defaultBaseURL }
    public var authValueFormat: String { authHeaderValueFormat }
}
