//
//  UnavailableSpeechProvider.swift
//  Echo
//
//  Temporary Phase 2 implementation. It establishes factory resolution and
//  deliberately performs no networking or AI work.
//

import Foundation

final class UnavailableSpeechProvider: SpeechProvider {
    let config: ProviderConfig

    init(config: ProviderConfig) {
        self.config = config
    }

    func transcribe(
        audioFile: URL,
        model: String,
        language: String?
    ) async throws -> TranscriptionResult {
        throw ProviderError.providerNotImplemented(provider: config.id)
    }
}
