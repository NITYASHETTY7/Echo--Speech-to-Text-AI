//
//  LLMProvider.swift
//  EchoCore
//
//  Protocol for LLM text-completion providers.
//  Mirrors Android's domain.ai.AIProvider interface exactly.
//
//  Every AI feature (grammar correction, rewrite, translation) uses this protocol.
//  No feature may directly instantiate a provider client.
//

import Foundation

// MARK: - LLMProvider

public protocol LLMProvider: Sendable {
    /// Machine-readable identifier, e.g. "groq", "openai", "gemini".
    var id: String { get }
    /// Human-readable display name shown in the UI.
    var name: String { get }
    /// The default chat/completion model for this provider.
    var defaultModel: String { get }

    /// Generate a text completion.
    /// - Parameters:
    ///   - systemPrompt: Optional system instruction (nil → provider omits it).
    ///   - userPrompt: The source text to process.
    ///   - modelOverride: Override the default model for this call only.
    /// - Returns: The generated text on success, or an error on failure.
    func generateCompletion(
        systemPrompt: String?,
        userPrompt: String,
        modelOverride: String?
    ) async -> Result<String, Error>
}

// MARK: - LLMError

/// Typed errors for LLM operations. Mirrors Android's AIError sealed class.
public enum LLMError: LocalizedError {
    case networkFailure(String)
    case invalidAPIKey
    case rateLimitExceeded
    case timeout
    case malformedResponse(String)
    case cancelled
    case providerUnavailable(String)
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .networkFailure(let msg):      return "Network error: \(msg)"
        case .invalidAPIKey:                return "Invalid or missing API key."
        case .rateLimitExceeded:            return "Rate limit exceeded. Please wait and try again."
        case .timeout:                      return "Request timed out."
        case .malformedResponse(let msg):   return "Unexpected response: \(msg)"
        case .cancelled:                    return "Operation was cancelled."
        case .providerUnavailable(let p):   return "\(p) is currently unavailable."
        case .unknown(let msg):             return msg
        }
    }
}
