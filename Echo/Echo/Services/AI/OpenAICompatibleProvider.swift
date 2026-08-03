//
//  OpenAICompatibleProvider.swift
//  Echo
//
//  Shared provider for Groq, OpenAI, OpenRouter, Azure OpenAI, and Custom
//  endpoints that implement the OpenAI audio transcriptions API.
//
//  Android source of truth:
//    android/.../speech/provider/OpenAICompatibleProvider.kt
//

import Foundation
import os

final class OpenAICompatibleProvider: SpeechProvider {
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
        EchoLog.ai.debug("[OpenAICompatible] provider=\(self.config.displayName, privacy: .public) model=\(model, privacy: .public)")

        // ── Pre-flight ────────────────────────────────────────────────────────
        let audioData = try loadAudio(from: audioFile)

        let baseURL = config.defaultBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = URL(string: "\(baseURL)/audio/transcriptions")!
        let authValue = String(format: config.authHeaderValueFormat, apiKey)

        // ── Build multipart body (Android field order preserved) ──────────────
        var form = MultipartFormData()
        form.addFile(
            name: "file",
            fileName: audioFile.lastPathComponent,
            mimeType: "audio/mp4",
            data: audioData
        )
        form.addTextField(name: "model", value: model)

        if config.capabilities.supportsVerboseJSON {
            form.addTextField(name: "response_format", value: "verbose_json")
        }
        if config.capabilities.supportsTemperature {
            form.addTextField(name: "temperature", value: "0")
        }
        if config.capabilities.supportsPrompt {
            form.addTextField(name: "prompt", value: AppConfig.Hallucination.transcriptionPrompt)
        }
        if config.capabilities.supportsLanguageSelection,
           let lang = language, !lang.isEmpty, lang.lowercased() != "auto" {
            form.addTextField(name: "language", value: lang)
        }

        let httpRequest = form.makeRequest(
            url: url,
            headers: [config.authHeaderName: authValue]
        )

        // ── Execute ────────────────────────────────────────────────────────────
        let response = try await httpClient.execute(httpRequest)

        // ── Parse verbose_json ─────────────────────────────────────────────────
        guard let root = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any] else {
            return TranscriptionResult(text: "")
        }
        let text = (root["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return TranscriptionResult(text: "") }

        // ── Hallucination guard (verbose_json providers only) ──────────────────
        if config.capabilities.supportsVerboseJSON {
            let segments = root["segments"] as? [[String: Any]]
            guard HallucinationFilter.passes(text: text, segments: segments) else {
                EchoLog.ai.debug("[OpenAICompatible] hallucination discarded: \(text.prefix(80), privacy: .private)")
                return TranscriptionResult(text: "")
            }
        }

        EchoLog.ai.debug("[OpenAICompatible] transcript length=\(text.count, privacy: .public)")
        return TranscriptionResult(text: text)
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
