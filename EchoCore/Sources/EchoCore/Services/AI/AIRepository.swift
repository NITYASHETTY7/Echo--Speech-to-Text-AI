//
//  AIRepository.swift
//  EchoCore
//
//  Repository protocol for AI text-completion operations.
//  Mirrors Android's domain.ai.AIRepository interface.
//  Firebase-free and provider-agnostic.
//

import Foundation

// MARK: - AIRepository

public protocol AIRepository: AnyObject, Sendable {

    /// Execute a prompt against the currently selected LLM provider.
    /// - Parameters:
    ///   - systemPrompt: Optional system instruction (nil → omitted).
    ///   - userPrompt: Source text to process.
    ///   - model: Override the default model for this call only.
    /// - Returns: Generated text on success.
    func executePrompt(
        systemPrompt: String?,
        userPrompt: String,
        model: String?
    ) async -> Result<String, Error>

    /// Persist a new version to local storage.
    func saveVersion(_ version: TranscriptVersion) async -> Result<Void, Error>

    /// Retrieve all versions for a given transcript, ordered oldest-first.
    func getVersions(forTranscriptId id: String) async -> [TranscriptVersion]

    /// The display name of the currently active provider.
    var currentProviderName: String { get }
    /// The current default chat model.
    var currentChatModel: String { get }
}
