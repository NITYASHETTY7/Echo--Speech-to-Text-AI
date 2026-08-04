package com.echo.dictation.domain.ai

import android.util.Log
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class RewriteService @Inject constructor(
    private val aiRepository: AIRepository,
    private val promptRepository: PromptTemplateRepository,
    private val providerFactory: AIProviderFactory,
) {

    suspend fun rewriteWithPreset(
        transcriptId: String,
        sourceText: String,
        templateId: String,
        targetLanguage: String = "English",
    ): Result<TranscriptVersion> {
        val template = promptRepository.getTemplate(templateId)
            ?: return Result.failure(IllegalArgumentException("Template not found: $templateId"))

        val providerName = safeProviderName()
        val modelName    = safeModelName()
        Log.d(TAG, "Executing rewrite preset '$templateId' for transcript $transcriptId via $providerName (lang=$targetLanguage)")

        // Append output language instruction to the template's system prompt
        val systemPromptWithLanguage = if (targetLanguage.isNotBlank() && targetLanguage != "English") {
            "${template.systemPrompt}\n\nIMPORTANT: Write the entire output in $targetLanguage."
        } else {
            template.systemPrompt
        }

        val result = aiRepository.executePrompt(
            systemPrompt = systemPromptWithLanguage,
            userPrompt   = sourceText,
        )

        return result.mapCatching { rewrittenText ->
            val version = TranscriptVersion(
                id           = UUID.randomUUID().toString(),
                transcriptId = transcriptId,
                versionType  = template.targetVersionType,
                createdAt    = System.currentTimeMillis(),
                provider     = providerName,
                model        = modelName,
                content      = rewrittenText,
                metadata     = mapOf(
                    "template_id" to templateId,
                    "template_title" to template.title,
                    "output_language" to targetLanguage,
                ),
            )
            aiRepository.saveVersion(version)
            version
        }
    }

    suspend fun rewriteWithCustomPrompt(
        transcriptId: String,
        sourceText: String,
        customInstruction: String,
        targetLanguage: String = "English",
    ): Result<TranscriptVersion> {
        require(customInstruction.isNotBlank()) { "Custom instruction must not be blank" }

        // Append output language instruction when the user has selected a non-default language
        val languageClause = if (targetLanguage.isNotBlank() && targetLanguage != "English") {
            "\n\nIMPORTANT: Write the entire output in $targetLanguage."
        } else {
            ""
        }

        val systemPrompt = """You are an expert writing assistant.
Apply the following instruction to the provided transcript.
Return only the transformed text without commentary.

Instruction: $customInstruction$languageClause""".trimIndent()

        val providerName = safeProviderName()
        val modelName    = safeModelName()
        Log.d(TAG, "Executing custom rewrite for transcript $transcriptId via $providerName (lang=$targetLanguage)")

        val result = aiRepository.executePrompt(
            systemPrompt = systemPrompt,
            userPrompt   = sourceText,
        )

        return result.mapCatching { rewrittenText ->
            val version = TranscriptVersion(
                id           = UUID.randomUUID().toString(),
                transcriptId = transcriptId,
                versionType  = VersionType.Custom,
                createdAt    = System.currentTimeMillis(),
                provider     = providerName,
                model        = modelName,
                content      = rewrittenText,
                metadata     = mapOf(
                    "custom_instruction" to customInstruction,
                    "output_language" to targetLanguage,
                ),
            )
            aiRepository.saveVersion(version)
            version
        }
    }

    private fun safeProviderName(): String =
        runCatching { providerFactory.currentProviderDisplayName() }.getOrDefault("Unknown")

    private fun safeModelName(): String =
        runCatching { providerFactory.getProvider().defaultModel }.getOrDefault("default")

    companion object {
        private const val TAG = "RewriteService"
    }
}
