//
//  GeminiProvider.swift
//  Echo
//
//  Google Gemini speech transcription.
//
//  Android source of truth:
//    android/.../speech/provider/GeminiProvider.kt
//
//  POST {baseURL}/v1beta/models/{model}:generateContent
//  Header: x-goog-api-key: {apiKey}
//  Body:   JSON with base64-encoded audio as inline_data
//
//  Response path: candidates[0].content.parts[0].text
//

import Foundation
import os

final class GeminiProvider: SpeechProvider {
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
        EchoLog.ai.debug("[Gemini] model=\(model, privacy: .public)")

        let audioData = try loadAudio(from: audioFile)
        let base64Audio = audioData.base64EncodedString()

        let baseURL = config.defaultBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = URL(string: "\(baseURL)/v1beta/models/\(model):generateContent")!

        // ── Build prompt (Android parity) ─────────────────────────────────────
        var prompt = "Transcribe the following audio exactly. "
        if config.capabilities.supportsLanguageSelection,
           let lang = language, !lang.isEmpty, lang.lowercased() != "auto" {
            prompt += "The audio is in \(lang). "
        }
        prompt += "Return only the transcript text with no additional commentary."

        // ── Build JSON body ────────────────────────────────────────────────────
        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": prompt],
                    ["inline_data": [
                        "mime_type": "audio/mp4",
                        "data": base64Audio,
                    ]],
                ],
            ]],
        ]

        let authValue = String(format: config.authHeaderValueFormat, apiKey)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = HTTPMethod.post.rawValue
        urlRequest.setValue(authValue, forHTTPHeaderField: config.authHeaderName)
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        // ── Execute ────────────────────────────────────────────────────────────
        let response = try await httpClient.execute(urlRequest)

        // ── Parse response ─────────────────────────────────────────────────────
        let transcript = parseResponse(from: response.data)
        EchoLog.ai.debug("[Gemini] transcript length=\(transcript.count, privacy: .public)")
        return TranscriptionResult(text: transcript)
    }

    // MARK: - Parsing

    private func parseResponse(from data: Data) -> String {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = root["candidates"] as? [[String: Any]],
            let content = candidates.first?["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]],
            let text = parts.first?["text"] as? String
        else { return "" }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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
