//
//  GeminiProvider.swift
//  EchoCore
//
//  Google Gemini speech transcription with resilient model resolution.
//
//  POST {baseURL}/v1beta/models/{model}:generateContent
//  Header: x-goog-api-key: {apiKey}
//  Body:   JSON with base64-encoded audio as inline_data
//  Response path: candidates[0].content.parts[0].text
//
//  Resilient model resolution
//  ──────────────────────────
//  Google periodically deprecates/renames Gemini models, causing 404 / 410
//  "model not found" errors that would otherwise break transcription until the
//  app is updated.  To make this future-proof WITHOUT hardcoding model names or
//  changing the SpeechProvider contract, model recovery is fully encapsulated
//  inside this provider:
//
//    1. Attempt transcription with the user-selected model (preserves preference).
//       • If that model was previously recorded as deprecated and a known-good
//         model is cached, start with the cached model instead.
//    2. On a model-not-found error (404 / 410), fetch the live model list from
//       GET /v1beta/models, then pick the newest stable `generateContent` model.
//    3. Retry with each candidate (bounded — never endless).
//    4. Cache the first model that succeeds so future calls start with it.
//    5. If every candidate fails, throw a clear, user-friendly error.
//
//  Nothing outside this file needs to know a model was swapped.
//

import Foundation
import os

public final class GeminiProvider: SpeechProvider {
    public let config: ProviderConfig
    private let apiKey: String
    private let httpClient: HTTPClient

    /// Maximum number of fallback models attempted after the first failure.
    private static let maxFallbackAttempts = 5

    // MARK: - Cache keys (UserDefaults)

    private static let workingModelKey    = "echo.gemini.workingModel"
    private static let deprecatedModelsKey = "echo.gemini.deprecatedModels"

    public init(config: ProviderConfig, apiKey: String, httpClient: HTTPClient) {
        self.config = config
        self.apiKey = apiKey
        self.httpClient = httpClient
    }

    // MARK: - SpeechProvider

    public func transcribe(
        audioFile: URL,
        model: String,
        language: String?
    ) async throws -> TranscriptionResult {

        // Load audio once; reused across any retries.
        let audioData   = try loadAudio(from: audioFile)
        let base64Audio = audioData.base64EncodedString()
        let prompt      = buildPrompt(language: language)

        // Determine the starting model.  Preserve the user's preference unless
        // that exact model is already known to be deprecated AND we have a
        // cached working replacement — in which case skip the guaranteed failure.
        var deprecated = loadDeprecatedModels()
        var startModel = model
        if deprecated.contains(model), let working = loadWorkingModel(), working != model {
            EchoLog.ai.info("[Gemini] requested model \(model, privacy: .public) is known-deprecated — starting with cached model \(working, privacy: .public)")
            startModel = working
        }

        // ── Attempt 1: the starting model ────────────────────────────────────
        do {
            let text = try await performTranscription(
                model: startModel, prompt: prompt, base64Audio: base64Audio
            )
            cacheWorkingModel(startModel)
            return TranscriptionResult(text: text)
        } catch let error where isModelUnavailable(error) {
            EchoLog.ai.warning("[Gemini] model \(startModel, privacy: .public) unavailable — resolving replacement")
            deprecated.insert(startModel)
            saveDeprecatedModels(deprecated)
        }
        // Any non-model error is rethrown by performTranscription and never reaches here.

        // ── Recovery: fetch live models and try the best candidates ──────────
        let liveModels = (try? await fetchAvailableModels()) ?? []
        EchoLog.ai.info("[Gemini] fetched \(liveModels.count, privacy: .public) live models for recovery")

        let candidates = orderedCandidates(from: liveModels, excluding: deprecated.union([startModel, model]))
        EchoLog.ai.info("[Gemini] fallback candidates: \(candidates.prefix(Self.maxFallbackAttempts).joined(separator: ", "), privacy: .public)")

        for candidate in candidates.prefix(Self.maxFallbackAttempts) {
            do {
                let text = try await performTranscription(
                    model: candidate, prompt: prompt, base64Audio: base64Audio
                )
                EchoLog.ai.info("[Gemini] recovered with model \(candidate, privacy: .public)")
                cacheWorkingModel(candidate)
                return TranscriptionResult(text: text)
            } catch let error where isModelUnavailable(error) {
                EchoLog.ai.warning("[Gemini] candidate \(candidate, privacy: .public) also unavailable — trying next")
                deprecated.insert(candidate)
                saveDeprecatedModels(deprecated)
                continue
            }
            // Non-model errors propagate out of performTranscription.
        }

        // ── Every fallback failed → clear, user-friendly error ───────────────
        EchoLog.ai.error("[Gemini] no compatible model found after \(candidates.count, privacy: .public) candidates")
        throw ProviderError.invalidConfiguration(
            provider: config.id,
            reason: "The selected Gemini model is no longer available and no compatible replacement could be found. Please choose another model in Settings."
        )
    }

    // MARK: - Single transcription attempt

    private func performTranscription(
        model: String,
        prompt: String,
        base64Audio: String
    ) async throws -> String {
        let baseURL = config.defaultBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(baseURL)/v1beta/models/\(model):generateContent") else {
            throw ProviderError.invalidConfiguration(provider: config.id, reason: "Invalid model endpoint URL.")
        }

        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": prompt],
                    ["inline_data": ["mime_type": "audio/mp4", "data": base64Audio]],
                ],
            ]],
        ]

        let authValue = String(format: config.authHeaderValueFormat, apiKey)
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue(authValue, forHTTPHeaderField: config.authHeaderName)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        EchoLog.ai.debug("[Gemini] transcribe attempt model=\(model, privacy: .public)")
        let response = try await httpClient.execute(request)
        return parseResponse(from: response.data)
    }

    // MARK: - Live model discovery

    /// Fetches the provider's current model list via GET /v1beta/models.
    private func fetchAvailableModels() async throws -> [String] {
        let baseURL = config.defaultBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(baseURL)/v1beta/models?key=\(apiKey)") else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.get.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let response = try await httpClient.execute(request)
        guard let root   = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any],
              let models = root["models"] as? [[String: Any]] else { return [] }

        return models.compactMap { m -> String? in
            guard let name = m["name"] as? String else { return nil }
            let methods = m["supportedGenerationMethods"] as? [String] ?? []
            guard methods.contains("generateContent") else { return nil }
            // "models/gemini-2.0-flash" → "gemini-2.0-flash"
            return name.hasPrefix("models/") ? String(name.dropFirst(7)) : name
        }
    }

    /// Orders live models best-first for speech transcription, excluding any
    /// already-tried or known-deprecated models.
    private func orderedCandidates(from models: [String], excluding: Set<String>) -> [String] {
        models
            .filter { !excluding.contains($0) }
            .filter { $0.lowercased().contains("gemini") }
            .sorted { score(for: $0) > score(for: $1) }
    }

    /// Heuristic score: newest version + "flash" (fast, ideal for audio) win;
    /// experimental/preview and non-transcription variants are penalised.
    private func score(for model: String) -> Double {
        let n = model.lowercased()
        var s = 0.0
        if let version = extractVersion(from: n) { s += version * 100 }   // 2.5 → 250
        if n.contains("flash") { s += 30 }        // flash is fast & cheap → best for transcription
        if n.contains("pro")   { s += 10 }
        if n.contains("exp") || n.contains("preview") { s -= 200 }  // prefer stable
        if n.contains("thinking") { s -= 50 }
        // Non-transcription model families should never be selected for audio.
        if n.contains("tts") || n.contains("image") || n.contains("embedding") || n.contains("vision") {
            s -= 1000
        }
        return s
    }

    /// Extracts the numeric version from a Gemini model id (e.g. "gemini-2.5-flash" → 2.5).
    private func extractVersion(from model: String) -> Double? {
        guard let range = model.range(of: #"[0-9]+(\.[0-9]+)?"#, options: .regularExpression) else {
            return nil
        }
        return Double(model[range])
    }

    // MARK: - Model-unavailable detection

    /// True when the error indicates the model is missing/deprecated (404 / 410).
    private func isModelUnavailable(_ error: Error) -> Bool {
        guard let networkError = error as? NetworkError else { return false }
        switch networkError {
        case .notFound:                       return true   // HTTP 404
        case .unexpectedStatus(let code):     return code == 410 || code == 404
        default:                              return false
        }
    }

    // MARK: - Cache (UserDefaults)

    private func loadWorkingModel() -> String? {
        UserDefaults.standard.string(forKey: Self.workingModelKey)
    }

    private func cacheWorkingModel(_ model: String) {
        UserDefaults.standard.set(model, forKey: Self.workingModelKey)
    }

    private func loadDeprecatedModels() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Self.deprecatedModelsKey) ?? [])
    }

    private func saveDeprecatedModels(_ models: Set<String>) {
        UserDefaults.standard.set(Array(models), forKey: Self.deprecatedModelsKey)
    }

    // MARK: - Request/response helpers

    private func buildPrompt(language: String?) -> String {
        var prompt = "Transcribe the following audio exactly. "
        if config.capabilities.supportsLanguageSelection,
           let lang = language, !lang.isEmpty, lang.lowercased() != "auto" {
            prompt += "The audio is in \(lang). "
        }
        prompt += "Return only the transcript text with no additional commentary."
        return prompt
    }

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
