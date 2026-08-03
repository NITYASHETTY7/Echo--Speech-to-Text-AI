//
//  GeminiLLMProvider.swift
//  EchoCore
//
//  LLMProvider for Google Gemini's generateContent REST API.
//  Uses text-only path (no audio) for grammar/rewrite operations.
//  System prompt is sent as the first user+model exchange (Gemini v1beta convention).
//

import Foundation
import os

public final class GeminiLLMProvider: LLMProvider {

    public let id: String    = "gemini"
    public let name: String  = "Google Gemini"
    public var defaultModel: String

    private let apiKey: String
    private let baseURL: String
    private let httpClient: HTTPClient
    private let logger = Logger(subsystem: "com.echo.echocore", category: "GeminiLLM")

    public init(
        apiKey: String,
        defaultModel: String = "gemini-1.5-flash",
        baseURL: String = "https://generativelanguage.googleapis.com/",
        httpClient: HTTPClient = HTTPClient()
    ) {
        self.apiKey = apiKey
        self.defaultModel = defaultModel
        self.baseURL = baseURL.hasSuffix("/") ? baseURL : baseURL + "/"
        self.httpClient = httpClient
    }

    public func generateCompletion(
        systemPrompt: String?,
        userPrompt: String,
        modelOverride: String? = nil
    ) async -> Result<String, Error> {
        let model = modelOverride ?? defaultModel
        let urlString = "\(baseURL)v1beta/models/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            return .failure(LLMError.malformedResponse("Invalid Gemini URL"))
        }

        var contents: [[String: Any]] = []
        if let system = systemPrompt, !system.isEmpty {
            contents.append([
                "role": "user",
                "parts": [["text": system]] as [[String: Any]]
            ])
            contents.append([
                "role": "model",
                "parts": [["text": "Understood."]] as [[String: Any]]
            ])
        }
        contents.append([
            "role": "user",
            "parts": [["text": userPrompt]] as [[String: Any]]
        ])

        let bodyObject: [String: Any] = [
            "contents":         contents,
            "generationConfig": ["temperature": 0.2, "maxOutputTokens": 4096] as [String: Any],
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyObject) else {
            return .failure(LLMError.malformedResponse("Failed to serialize Gemini request"))
        }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let response = try await httpClient.execute(request)
            return parseGeminiResponse(response.data)
        } catch let networkError as NetworkError {
            switch networkError {
            case .timeout:   return .failure(LLMError.timeout)
            case .cancelled: return .failure(LLMError.cancelled)
            default:         return .failure(LLMError.networkFailure(networkError.localizedDescription))
            }
        } catch {
            return .failure(LLMError.unknown(error.localizedDescription))
        }
    }

    private func parseGeminiResponse(_ data: Data) -> Result<String, Error> {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errObj = json["error"] as? [String: Any],
               let msg = errObj["message"] as? String {
                if msg.lowercased().contains("api key") { return .failure(LLMError.invalidAPIKey) }
                return .failure(LLMError.unknown(msg))
            }
            return .failure(LLMError.malformedResponse("Cannot parse Gemini response"))
        }
        return .success(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
