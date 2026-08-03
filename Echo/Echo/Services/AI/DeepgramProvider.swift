//
//  DeepgramProvider.swift
//  Echo
//
//  Deepgram pre-recorded audio transcription.
//
//  Android source of truth:
//    android/.../speech/provider/DeepgramProvider.kt
//
//  POST {baseURL}/v1/listen?model={model}&smart_format=true[&language={language}]
//  Authorization: Token {apiKey}
//  Content-Type: audio/mp4
//  Body: raw audio bytes
//
//  Response path: results.channels[0].alternatives[0].transcript
//

import Foundation
import os

final class DeepgramProvider: SpeechProvider {
    let config: ProviderConfig
    private let apiKey: String
    private let httpClient: HTTPClient

    init(config: ProviderConfig, apiKey: String, httpClient: HTTPClient) {
        self.config = config
        self.apiKey = apiKey
        self.httpClient = httpClient
    }

    func transcribe(
        audioFile: URL,
        model: String,
        language: String?
    ) async throws -> TranscriptionResult {
        EchoLog.ai.debug("[Deepgram] model=\(model, privacy: .public)")

        let audioData = try loadAudio(from: audioFile)

        // ── Build URL with query parameters ──────────────────────────────────
        let baseURL = config.defaultBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var components = URLComponents(string: "\(baseURL)/v1/listen")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "model", value: model),
            URLQueryItem(name: "smart_format", value: "true"),
        ]
        if config.capabilities.supportsLanguageSelection,
           let lang = language, !lang.isEmpty, lang.lowercased() != "auto" {
            queryItems.append(URLQueryItem(name: "language", value: lang))
        }
        components.queryItems = queryItems
        let url = components.url!

        // ── Build raw-bytes request ────────────────────────────────────────────
        let authValue = String(format: config.authHeaderValueFormat, apiKey)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = HTTPMethod.post.rawValue
        urlRequest.setValue(authValue, forHTTPHeaderField: config.authHeaderName)
        urlRequest.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = audioData

        // ── Execute ────────────────────────────────────────────────────────────
        let response = try await httpClient.execute(urlRequest)

        // ── Parse response ─────────────────────────────────────────────────────
        let transcript = parseTranscript(from: response.data)
        EchoLog.ai.debug("[Deepgram] transcript length=\(transcript.count, privacy: .public)")
        return TranscriptionResult(text: transcript)
    }

    // MARK: - Parsing

    private func parseTranscript(from data: Data) -> String {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let results = root["results"] as? [String: Any],
            let channels = results["channels"] as? [[String: Any]],
            let firstChannel = channels.first,
            let alternatives = firstChannel["alternatives"] as? [[String: Any]],
            let firstAlt = alternatives.first,
            let transcript = firstAlt["transcript"] as? String
        else { return "" }
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Helpers

    private func loadAudio(from url: URL) throws -> Data {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ProviderError.invalidConfiguration(
                provider: config.id,
                reason: "Audio file not found: \(url.lastPathComponent)"
            )
        }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            throw ProviderError.invalidConfiguration(
                provider: config.id,
                reason: "Audio file is empty: \(url.lastPathComponent)"
            )
        }
        return data
    }
}
