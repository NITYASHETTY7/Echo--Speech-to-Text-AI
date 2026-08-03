//
//  ProviderCapabilities.swift
//  Echo
//
//  Declarative provider behavior. Consumers should use these flags rather than
//  branching on ProviderId for request/UI capabilities.
//

import Foundation

struct ProviderCapabilities: Equatable, Sendable {
    let supportsStreaming: Bool
    let supportsLanguageSelection: Bool
    let supportsPrompt: Bool
    let supportsVerboseJSON: Bool
    let supportsWordTimestamps: Bool
    let supportsTemperature: Bool
    let supportsCustomBaseURL: Bool
    let supportsCustomModel: Bool
    let supportsConnectionTest: Bool

    init(
        supportsStreaming: Bool = false,
        supportsLanguageSelection: Bool = false,
        supportsPrompt: Bool = false,
        supportsVerboseJSON: Bool = false,
        supportsWordTimestamps: Bool = false,
        supportsTemperature: Bool = false,
        supportsCustomBaseURL: Bool = false,
        supportsCustomModel: Bool = false,
        supportsConnectionTest: Bool = false
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
    }
}
