//
//  UnavailableSpeechProvider.swift
//  Echo
//
//  Temporary Phase 2 implementation. It establishes factory resolution and
//  deliberately performs no networking or AI work.
//

import Foundation

public final class UnavailableSpeechProvider: SpeechProvider {
    public let config: ProviderConfig

    public init(config: ProviderConfig) {
        self.config = config
    }

    public func transcribe(
        audioFile: URL,
        model: String,
        language: String?
    ) async throws -> TranscriptionResult {
        throw ProviderError.providerNotImplemented(provider: config.id)
    }
}
