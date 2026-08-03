//
//  ProviderError.swift
//  Echo
//
//  Typed provider infrastructure errors. Network/API errors are intentionally
//  not defined here; they belong to Phase 3/4.
//

import Foundation

enum ProviderError: LocalizedError, Equatable, Sendable {
    case missingAPIKey(provider: ProviderId)
    case missingBaseURL(provider: ProviderId)
    case invalidConfiguration(provider: ProviderId, reason: String)
    case unsupportedProvider(rawValue: String)
    case providerNotImplemented(provider: ProviderId)

    var errorDescription: String? {
        switch self {
        case let .missingAPIKey(provider):
            return "No API key configured for \(provider.displayName). Open Echo → Settings to add your key."
        case let .missingBaseURL(provider):
            return "\(provider.displayName) requires a Base URL. Open Echo → Settings to configure."
        case let .invalidConfiguration(provider, reason):
            return "Invalid configuration for \(provider.displayName): \(reason)"
        case let .unsupportedProvider(rawValue):
            return "Unsupported speech provider: \(rawValue)"
        case let .providerNotImplemented(provider):
            return "\(provider.displayName) transcription is not implemented yet."
        }
    }
}
