//
//  NullAIRepository.swift
//  Echo
//
//  No-op AIRepository used as a safe fallback before AIService is initialized.
//  Returns errors on all operations — ensures the app never crashes with a nil
//  AIService, but makes clear that the provider is not ready.
//

import Foundation
import EchoCore

final class NullAIRepository: AIRepository, @unchecked Sendable {
    var currentProviderName: String { "Not configured" }
    var currentChatModel: String { "none" }

    func executePrompt(systemPrompt: String?, userPrompt: String, model: String?) async -> Result<String, Error> {
        .failure(AIServiceError.providerNotConfigured)
    }

    func saveVersion(_ version: TranscriptVersion) async -> Result<Void, Error> {
        .failure(AIServiceError.providerNotConfigured)
    }

    func getVersions(forTranscriptId id: String) async -> [TranscriptVersion] { [] }
}
