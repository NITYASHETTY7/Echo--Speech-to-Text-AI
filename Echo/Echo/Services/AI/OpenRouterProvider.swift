//
//  OpenRouterProvider.swift
//  Echo
//
//  Thin wrapper over OpenAICompatibleProvider.
//

import Foundation

final class OpenRouterProvider: SpeechProvider {
    let config: ProviderConfig
    private let inner: OpenAICompatibleProvider

    init(apiKey: String, httpClient: HTTPClient) {
        self.config = ProviderRegistry.configuration(for: .openRouter)
        self.inner = OpenAICompatibleProvider(config: config, apiKey: apiKey, httpClient: httpClient)
    }

    func transcribe(audioFile: URL, model: String, language: String?) async throws -> TranscriptionResult {
        try await inner.transcribe(audioFile: audioFile, model: model, language: language)
    }
}
