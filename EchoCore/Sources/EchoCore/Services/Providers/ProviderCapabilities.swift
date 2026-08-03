//
//  ProviderCapabilities.swift
//  EchoCore
//
//  Declarative provider behavior flags.
//  V3 additions: LLM/chat completion capability flags.
//

import Foundation

public struct ProviderCapabilities: Equatable, Sendable {
    // ── Speech / transcription ────────────────────────────────────────────────
    public let supportsStreaming: Bool
    public let supportsLanguageSelection: Bool
    public let supportsPrompt: Bool
    public let supportsVerboseJSON: Bool
    public let supportsWordTimestamps: Bool
    public let supportsTemperature: Bool
    public let supportsCustomBaseURL: Bool
    public let supportsCustomModel: Bool
    public let supportsConnectionTest: Bool

    // ── LLM / chat completion ─────────────────────────────────────────────────
    /// Provider supports /v1/chat/completions (or equivalent) for text generation.
    public let supportsTextCompletion: Bool
    /// Provider accepts a system role message.
    public let supportsSystemPrompt: Bool

    public init(
        supportsStreaming: Bool = false,
        supportsLanguageSelection: Bool = false,
        supportsPrompt: Bool = false,
        supportsVerboseJSON: Bool = false,
        supportsWordTimestamps: Bool = false,
        supportsTemperature: Bool = false,
        supportsCustomBaseURL: Bool = false,
        supportsCustomModel: Bool = false,
        supportsConnectionTest: Bool = false,
        supportsTextCompletion: Bool = false,
        supportsSystemPrompt: Bool = false
    ) {
        self.supportsStreaming = supportsStreaming
        self.supportsLanguageSelection = supportsLanguageSelection
        self.supportsPrompt = supportsPrompt
        self.supportsVerboseJSON = supportsVerboseJSON
        self.supportsWordTimestamps = supportsWordTimestamps
        self.supportsTemperature = supportsTemperature
        self.supportsCustomBaseURL = supportsCustomBaseURL
        self.supportsCustomModel = supportsCustomModel
        self.supportsConnectionTest = supportsConnectionTest
        self.supportsTextCompletion = supportsTextCompletion
        self.supportsSystemPrompt = supportsSystemPrompt
    }
}
