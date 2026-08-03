//
//  AIRepositoryImpl.swift
//  Echo
//
//  Concrete implementation of AIRepository.
//  Bridges ProviderFactory (for LLM calls) and TranscriptionStore (for version persistence).
//  Mirrors Android's AIRepositoryImpl.
//

import Foundation
import EchoCore
import os

// MARK: - AIRepositoryImpl

@MainActor
final class AIRepositoryImpl: AIRepository, @unchecked Sendable {

    // MARK: - Dependencies

    private let providerFactory: ProviderFactory
    private let store: any TranscriptionStoreProtocol
    private let logger = Logger(subsystem: "com.echo.app", category: "AIRepository")

    // MARK: - Init

    init(providerFactory: ProviderFactory, store: any TranscriptionStoreProtocol) {
        self.providerFactory = providerFactory
        self.store = store
    }

    // MARK: - AIRepository

    var currentProviderName: String {
        providerFactory.currentProviderDisplayName
    }

    var currentChatModel: String {
        providerFactory.currentDefaultChatModel
    }

    func executePrompt(
        systemPrompt: String?,
        userPrompt: String,
        model: String?
    ) async -> Result<String, Error> {
        do {
            let llm = try providerFactory.getLLMProvider()
            return await llm.generateCompletion(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                modelOverride: model
            )
        } catch let providerError as ProviderError {
            logger.error("executePrompt: provider error — \(providerError.localizedDescription, privacy: .public)")
            return .failure(providerError)
        } catch {
            logger.error("executePrompt: unexpected error — \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }

    func saveVersion(_ version: TranscriptVersion) async -> Result<Void, Error> {
        do {
            try store.insertVersion(version)
            return .success(())
        } catch {
            logger.error("saveVersion: \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }

    func getVersions(forTranscriptId id: String) async -> [TranscriptVersion] {
        (try? store.fetchVersions(forTranscriptId: id)) ?? []
    }
}
