//
//  GroqProvider.swift
//  Echo
//
//  Thin wrapper over OpenAICompatibleProvider.
//  All transcription logic lives in OpenAICompatibleProvider.
//

import Foundation

public final class GroqProvider: SpeechProvider {
    public let config: ProviderConfig
    private let inner: OpenAICompatibleProvider

    public init(apiKey: String, httpClient: HTTPClient) {
        self.config = ProviderRegistry.configuration(for: .groq)
        self.inner = OpenAICompatibleProvider(config: config, apiKey: apiKey, httpClient: httpClient)
    }

    public func transcribe(audioFile: URL, model: String, language: String?) async throws -> TranscriptionResult {
        try await inner.transcribe(audioFile: audioFile, model: model, language: language)
    }
}
