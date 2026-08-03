//
//  ProviderId.swift
//  Echo
//
//  Provider identity matching Android's ProviderId enum.
//

import Foundation

enum ProviderId: String, CaseIterable, Codable, Sendable {
    case groq = "GROQ"
    case openAI = "OPENAI"
    case openRouter = "OPENROUTER"
    case deepgram = "DEEPGRAM"
    case assemblyAI = "ASSEMBLYAI"
    case gemini = "GEMINI"
    case azure = "AZURE"
    case custom = "CUSTOM"

    var displayName: String {
        switch self {
        case .groq: return "Groq"
        case .openAI: return "OpenAI"
        case .openRouter: return "OpenRouter"
        case .deepgram: return "Deepgram"
        case .assemblyAI: return "AssemblyAI"
        case .gemini: return "Google Gemini"
        case .azure: return "Azure OpenAI"
        case .custom: return "Custom OpenAI-Compatible"
        }
    }
}
