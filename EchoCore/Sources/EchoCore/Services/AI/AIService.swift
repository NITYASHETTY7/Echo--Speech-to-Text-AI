//
//  AIService.swift
//  EchoCore
//
//  Central orchestrator for all AI processing operations.
//  Mirrors Android's domain.ai.AIService exactly:
//
//  Pipeline (post-transcription):
//    rawText → (grammar? → GrammarCorrected) → (autoEnhance? → AutoEnhanced)
//
//  On-demand rewrites:
//    applyPreset()     → any VersionType via PromptTemplate
//    applyCustom()     → VersionType.Custom
//    applyTranslation()→ VersionType.Translation
//
//  Graceful degradation: if a step fails, its version is not saved and the
//  previous text is forwarded (matching Android behaviour).
//
//  EchoCore is Firebase-free. AIService only depends on AIRepository (protocol)
//  and PromptTemplateRepository (pure value type).
//

import Foundation
import os

// MARK: - AIService

@MainActor
public final class AIService {

    // MARK: - Dependencies

    private let aiRepository: any AIRepository
    private let promptRepository: PromptTemplateRepository
    private let logger = Logger(subsystem: "com.echo.echocore", category: "AIService")

    // MARK: - Init

    public init(
        aiRepository: any AIRepository,
        promptRepository: PromptTemplateRepository = PromptTemplateRepository()
    ) {
        self.aiRepository = aiRepository
        self.promptRepository = promptRepository
    }

    // ──────────────────────────────────────────────────────────────────────────
    // MARK: Post-transcription pipeline
    // ──────────────────────────────────────────────────────────────────────────

    /// Runs the optional post-transcription AI pipeline and returns the final text.
    ///
    /// Pipeline:
    ///   rawText
    ///     → (if grammarEnabled)  Grammar Correction → saves GrammarCorrected
    ///     → (if autoEnhance)     Auto Enhance       → saves AutoEnhanced
    ///
    /// Mirrors Android's AIService.processPostTranscription() exactly.
    public func processPostTranscription(
        transcriptId: String,
        rawText: String,
        grammarEnabled: Bool = false,
        autoEnhanceEnabled: Bool = false
    ) async -> String {
        guard !rawText.isEmpty else { return rawText }
        guard grammarEnabled || autoEnhanceEnabled else { return rawText }

        var currentText = rawText

        // ── Step 1: Grammar Correction ────────────────────────────────────────
        if grammarEnabled {
            let result = await aiRepository.executePrompt(
                systemPrompt: PromptTemplateRepository.grammarCorrectionSystemPrompt,
                userPrompt: rawText,
                model: nil
            )
            switch result {
            case .success(let corrected):
                let version = TranscriptVersion(
                    transcriptId: transcriptId,
                    versionType: .grammarCorrected,
                    provider: aiRepository.currentProviderName,
                    model: aiRepository.currentChatModel,
                    content: corrected
                )
                _ = await aiRepository.saveVersion(version)
                currentText = corrected
                logger.debug("Grammar correction complete for \(transcriptId, privacy: .public)")
            case .failure(let err):
                logger.warning("Grammar correction failed: \(err.localizedDescription, privacy: .public)")
                // currentText stays as rawText; pipeline continues
            }
        }

        // ── Step 2: Auto Enhance ──────────────────────────────────────────────
        if autoEnhanceEnabled {
            let result = await aiRepository.executePrompt(
                systemPrompt: PromptTemplateRepository.autoEnhanceSystemPrompt,
                userPrompt: currentText,
                model: nil
            )
            switch result {
            case .success(let enhanced):
                let version = TranscriptVersion(
                    transcriptId: transcriptId,
                    versionType: .autoEnhanced,
                    provider: aiRepository.currentProviderName,
                    model: aiRepository.currentChatModel,
                    content: enhanced,
                    metadata: ["source": "auto_enhance"]
                )
                _ = await aiRepository.saveVersion(version)
                currentText = enhanced
                logger.debug("Auto enhance complete for \(transcriptId, privacy: .public)")
            case .failure(let err):
                logger.warning("Auto enhance failed: \(err.localizedDescription, privacy: .public)")
            }
        }

        return currentText
    }

    // ──────────────────────────────────────────────────────────────────────────
    // MARK: On-demand rewrites
    // ──────────────────────────────────────────────────────────────────────────

    /// Apply a named preset (professional, summary, meeting_notes, etc.).
    ///
    /// `outputLanguage` is the user's selected output language (e.g. "English",
    /// "Kannada").  An unconditional OUTPUT LANGUAGE directive is appended to
    /// every system prompt so the model always responds in the chosen language,
    /// regardless of the input transcript's language.
    ///
    /// Mirrors Android's AIService.applyRewritePreset().
    public func applyPreset(
        transcriptId: String,
        sourceText: String,
        templateId: String,
        outputLanguage: String = "English"
    ) async -> Result<TranscriptVersion, Error> {
        guard let template = promptRepository.getTemplate(templateId) else {
            return .failure(AIServiceError.templateNotFound(templateId))
        }

        logger.debug("Applying preset '\(templateId)' outputLang='\(outputLanguage)' for \(transcriptId, privacy: .public)")

        let systemPrompt = PromptTemplateRepository.presetSystemPrompt(
            template: template,
            outputLanguage: outputLanguage
        )

        let result = await aiRepository.executePrompt(
            systemPrompt: systemPrompt,
            userPrompt: sourceText,
            model: nil
        )

        return await result.asyncMap { rewrittenText in
            let version = TranscriptVersion(
                transcriptId: transcriptId,
                versionType: template.targetVersionType,
                provider: self.aiRepository.currentProviderName,
                model: self.aiRepository.currentChatModel,
                content: rewrittenText,
                metadata: [
                    "template_id": templateId,
                    "template_title": template.title,
                    "output_language": outputLanguage,
                ]
            )
            _ = await self.aiRepository.saveVersion(version)
            return version
        }
    }

    /// Apply a free-form custom instruction.
    ///
    /// `outputLanguage` overrides the output language unconditionally — the
    /// user's instruction text has no effect on which language is used.
    ///
    /// Mirrors Android's AIService.applyCustomRewrite().
    public func applyCustomRewrite(
        transcriptId: String,
        sourceText: String,
        instruction: String,
        outputLanguage: String = "English"
    ) async -> Result<TranscriptVersion, Error> {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(AIServiceError.emptyInstruction)
        }

        let systemPrompt = PromptTemplateRepository.customRewriteSystemPrompt(
            instruction: trimmed,
            outputLanguage: outputLanguage
        )

        logger.debug("Applying custom rewrite outputLang='\(outputLanguage)' for \(transcriptId, privacy: .public)")

        let result = await aiRepository.executePrompt(
            systemPrompt: systemPrompt,
            userPrompt: sourceText,
            model: nil
        )

        return await result.asyncMap { rewrittenText in
            let version = TranscriptVersion(
                transcriptId: transcriptId,
                versionType: .custom,
                provider: self.aiRepository.currentProviderName,
                model: self.aiRepository.currentChatModel,
                content: rewrittenText,
                metadata: [
                    "custom_instruction": trimmed,
                    "output_language": outputLanguage,
                ]
            )
            _ = await self.aiRepository.saveVersion(version)
            return version
        }
    }

    /// Translate to a target language.
    ///
    /// `targetLanguage` is the output language — the same parameter that
    /// populates the OUTPUT LANGUAGE directive in the prompt.
    ///
    /// Mirrors Android's AIService.applyTranslation().
    public func applyTranslation(
        transcriptId: String,
        sourceText: String,
        targetLanguage: String
    ) async -> Result<TranscriptVersion, Error> {
        let systemPrompt = PromptTemplateRepository.translationSystemPrompt(
            targetLanguage: targetLanguage
        )

        logger.debug("Applying translation targetLang='\(targetLanguage)' for \(transcriptId, privacy: .public)")

        let result = await aiRepository.executePrompt(
            systemPrompt: systemPrompt,
            userPrompt: sourceText,
            model: nil
        )

        return await result.asyncMap { translatedText in
            let version = TranscriptVersion(
                transcriptId: transcriptId,
                versionType: .translation,
                provider: self.aiRepository.currentProviderName,
                model: self.aiRepository.currentChatModel,
                content: translatedText,
                metadata: ["target_language": targetLanguage]
            )
            _ = await self.aiRepository.saveVersion(version)
            return version
        }
    }

    // ──────────────────────────────────────────────────────────────────────────
    // MARK: Version queries
    // ──────────────────────────────────────────────────────────────────────────

    public func getVersions(forTranscriptId id: String) async -> [TranscriptVersion] {
        await aiRepository.getVersions(forTranscriptId: id)
    }

    public func getAllTemplates() -> [PromptTemplate] {
        promptRepository.getAllTemplates()
    }
}

// MARK: - AIServiceError

public enum AIServiceError: LocalizedError {
    case templateNotFound(String)
    case emptyInstruction
    case providerNotConfigured

    public var errorDescription: String? {
        switch self {
        case .templateNotFound(let id): return "Prompt template '\(id)' not found."
        case .emptyInstruction:         return "Custom instruction cannot be empty."
        case .providerNotConfigured:    return "No AI provider is configured. Please add an API key in Settings."
        }
    }
}

// MARK: - Result async helper

private extension Result {
    func asyncMap<NewSuccess>(
        _ transform: (Success) async -> NewSuccess
    ) async -> Result<NewSuccess, Failure> {
        switch self {
        case .success(let value): return .success(await transform(value))
        case .failure(let error): return .failure(error)
        }
    }
}
