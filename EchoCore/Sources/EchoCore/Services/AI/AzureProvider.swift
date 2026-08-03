//
//  AzureProvider.swift
//  Echo
//
//  Thin wrapper over OpenAICompatibleProvider for Azure OpenAI deployments.
//  The config uses the user-supplied base URL and api-key header.
//

import Foundation

public final class AzureProvider: SpeechProvider {
    public let config: ProviderConfig
    private let inner: OpenAICompatibleProvider

    /// - Parameter config: Must be the Azure ProviderConfig with the user's
    ///   deployment base URL pre-filled as `defaultBaseURL`.
    public init(config: ProviderConfig, apiKey: String, httpClient: HTTPClient) {
        self.config = config
        self.inner = OpenAICompatibleProvider(config: config, apiKey: apiKey, httpClient: httpClient)
    }

    public func transcribe(audioFile: URL, model: String, language: String?) async throws -> TranscriptionResult {
        try await inner.transcribe(audioFile: audioFile, model: model, language: language)
    }
}
