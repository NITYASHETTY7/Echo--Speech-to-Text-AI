//
//  OpenAICompatibleLLMProvider.swift
//  EchoCore
//
//  LLMProvider implementation for all OpenAI /v1/chat/completions compatible
//  endpoints: Groq, OpenAI, OpenRouter, Azure OpenAI, and Custom endpoints.
//
//  Uses the existing HTTPClient from Services/Network.
//  temperature: 0.2 / max_tokens: 4096 — matches Android exactly.
//

import Foundation
import os

// MARK: - OpenAICompatibleLLMProvider

public final class OpenAICompatibleLLMProvider: LLMProvider {

    public let id: String
    public let name: String
    public let defaultModel: String

    private let baseURL: String
    private let apiKey: String
    private let httpClient: HTTPClient
    private let logger = Logger(subsystem: "com.echo.echocore", category: "LLM")

    public init(
        id: String,
        name: String,
        baseURL: String,
        defaultModel: String,
        apiKey: String,
        httpClient: HTTPClient = HTTPClient()
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL.hasSuffix("/") ? baseURL : baseURL + "/"
        self.defaultModel = defaultModel
        self.apiKey = apiKey
        self.httpClient = httpClient
    }

    public func generateCompletion(
        systemPrompt: String?,
        userPrompt: String,
        modelOverride: String? = nil
    ) async -> Result<String, Error> {
        let model = modelOverride ?? defaultModel
        let urlString = "\(baseURL)chat/completions"
        guard let url = URL(string: urlString) else {
            return .failure(LLMError.malformedResponse("Invalid URL: \(urlString)"))
        }

        var messages: [[String: String]] = []
        if let system = systemPrompt, !system.isEmpty {
            messages.append(["role": "system", "content": system])
        }
        messages.append(["role": "user", "content": userPrompt])

        let bodyObject: [String: Any] = [
            "model":       model,
            "messages":    messages,
            "temperature": 0.2,
            "max_tokens":  4096,
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyObject) else {
            return .failure(LLMError.malformedResponse("Failed to serialize request body"))
        }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let response = try await httpClient.execute(request)
            return parseResponse(response.data)
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

    private func parseResponse(_ data: Data) -> Result<String, Error> {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errObj = json["error"] as? [String: Any],
               let msg = errObj["message"] as? String {
                let lower = msg.lowercased()
                if lower.contains("api key") || lower.contains("authentication") {
                    return .failure(LLMError.invalidAPIKey)
                }
                return .failure(LLMError.unknown(msg))
            }
            return .failure(LLMError.malformedResponse("Cannot parse choices[0].message.content"))
        }
        return .success(content.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
