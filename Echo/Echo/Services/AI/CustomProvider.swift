//
//  CustomProvider.swift
//  Echo
//
//  Thin wrapper over OpenAICompatibleProvider for custom OpenAI-compatible
//  endpoints.  The config carries the user-supplied base URL.
//

import Foundation

final class CustomProvider: SpeechProvider {
    let config: ProviderConfig
    private let inner: OpenAICompatibleProvider

    init(config: ProviderConfig, apiKey: String, httpClient: HTTPClient) {
        self.config = config
        self.inner = OpenAICompatibleProvider(config: config, apiKey: apiKey, httpClient: httpClient)
    }

    func transcribe(audioFile: URL, model: String, language: String?) async throws -> TranscriptionResult {
        try await inner.transcribe(audioFile: audioFile, model: model, language: language)
    }
}
