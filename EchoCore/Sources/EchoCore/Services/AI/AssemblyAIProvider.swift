//
//  AssemblyAIProvider.swift
//  Echo
//
//  AssemblyAI transcription via the synchronous REST API.
//
//  Android source of truth:
//    android/.../speech/provider/AssemblyAIProvider.kt
//    MAX_POLL_ATTEMPTS = 60
//    POLL_INTERVAL_MS  = 2_000
//
//  Step 1 – Upload:  POST /v2/upload  (raw audio bytes)
//  Step 2 – Submit:  POST /v2/transcript  { audio_url, language_code? }
//  Step 3 – Poll:    GET  /v2/transcript/{id}  until status=completed|error
//
//  Auth: Authorization: {apiKey}  (no "Bearer" prefix — Android parity)
//

import Foundation
import os

public final class AssemblyAIProvider: SpeechProvider {
    public let config: ProviderConfig
    private let apiKey: String
    private let httpClient: HTTPClient

    // Android-parity constants
    private let maxPollAttempts = AppConfig.AssemblyAI.maxPollAttempts
    private let pollInterval    = AppConfig.AssemblyAI.pollInterval

    public init(config: ProviderConfig, apiKey: String, httpClient: HTTPClient) {
        self.config = config
        self.apiKey = apiKey
        self.httpClient = httpClient
    }

    public func transcribe(
        audioFile: URL,
        model: String,
        language: String?
    ) async throws -> TranscriptionResult {
        EchoLog.ai.debug("[AssemblyAI] start")

        let audioData = try loadAudio(from: audioFile)
        let baseURL = config.defaultBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let authValue = String(format: config.authHeaderValueFormat, apiKey)

        // ── Step 1: Upload audio ────────────────────────────────────────────
        let uploadURL = try await uploadAudio(data: audioData, baseURL: baseURL, authValue: authValue)
        EchoLog.ai.debug("[AssemblyAI] upload complete")

        // ── Step 2: Submit transcript job ───────────────────────────────────
        let transcriptID = try await submitTranscription(
            audioURL: uploadURL,
            language: language,
            baseURL: baseURL,
            authValue: authValue
        )
        EchoLog.ai.debug("[AssemblyAI] job id=\(transcriptID.prefix(8), privacy: .public)…")

        // ── Step 3: Poll until completion ────────────────────────────────────
        return try await pollForResult(id: transcriptID, baseURL: baseURL, authValue: authValue)
    }

    // MARK: - Step 1: Upload

    private func uploadAudio(data: Data, baseURL: String, authValue: String) async throws -> String {
        let url = URL(string: "\(baseURL)/v2/upload")!
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue(authValue, forHTTPHeaderField: config.authHeaderName)
        request.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let response = try await httpClient.execute(request)
        guard
            let root = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any],
            let uploadURL = root["upload_url"] as? String,
            !uploadURL.isEmpty
        else {
            throw NetworkError.decodingFailed(reason: "AssemblyAI did not return an upload_url")
        }
        return uploadURL
    }

    // MARK: - Step 2: Submit

    private func submitTranscription(
        audioURL: String,
        language: String?,
        baseURL: String,
        authValue: String
    ) async throws -> String {
        let url = URL(string: "\(baseURL)/v2/transcript")!
        var body: [String: Any] = ["audio_url": audioURL]
        if config.capabilities.supportsLanguageSelection,
           let lang = language, !lang.isEmpty, lang.lowercased() != "auto" {
            body["language_code"] = lang
        }

        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue(authValue, forHTTPHeaderField: config.authHeaderName)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let response = try await httpClient.execute(request)
        guard
            let root = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any],
            let id = root["id"] as? String, !id.isEmpty
        else {
            throw NetworkError.decodingFailed(reason: "AssemblyAI did not return a transcript id")
        }
        return id
    }

    // MARK: - Step 3: Poll

    private func pollForResult(id: String, baseURL: String, authValue: String) async throws -> TranscriptionResult {
        let url = URL(string: "\(baseURL)/v2/transcript/\(id)")!
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.get.rawValue
        request.setValue(authValue, forHTTPHeaderField: config.authHeaderName)

        for attempt in 1...maxPollAttempts {
            try await Task.sleep(for: .seconds(pollInterval))
            try Task.checkCancellation()

            let response = try await httpClient.execute(request)
            guard let root = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any] else {
                continue
            }

            let status = root["status"] as? String ?? ""
            EchoLog.ai.debug("[AssemblyAI] poll #\(attempt, privacy: .public) status=\(status, privacy: .public)")

            switch status {
            case "completed":
                let text = (root["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return TranscriptionResult(text: text)
            case "error":
                let message = root["error"] as? String ?? "Unknown AssemblyAI error"
                throw NetworkError.transportError(reason: message)
            default:
                break   // "queued" | "processing" → continue polling
            }
        }

        throw NetworkError.requestTimeout
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
