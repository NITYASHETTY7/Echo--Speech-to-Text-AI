package com.echo.dictation.domain.ai

import android.util.Log
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class RewriteService @Inject constructor(
    private val aiRepository: AIRepository,
    private val promptRepository: PromptTemplateRepository,
) {

    suspend fun rewriteWithPreset(
        transcriptId: String,
        sourceText: String,
        templateId: String
    ): Result<TranscriptVersion> {
        val template = promptRepository.getTemplate(templateId)
            ?: return Result.failure(IllegalArgumentException("Template not found: $templateId"))

        Log.d(TAG, "Executing rewrite preset '$templateId' for transcript $transcriptId")
        val result = aiRepository.executePrompt(
            systemPrompt = template.systemPrompt,
            userPrompt = sourceText
        )

        return result.mapCatching { rewrittenText ->
            val version = TranscriptVersion(
                id = UUID.randomUUID().toString(),
                transcriptId = transcriptId,
                versionType = template.targetVersionType,
                createdAt = System.currentTimeMillis(),
                provider = "Groq",
                model = "llama-3.3-70b-versatile",
                content = rewrittenText,
                metadata = mapOf("template_id" to templateId, "template_title" to template.title)
            )
            aiRepository.saveVersion(version)
            version
        }
    }

    suspend fun rewriteWithCustomPrompt(
        transcriptId: String,
        sourceText: String,
        customInstruction: String
    ): Result<TranscriptVersion> {
        require(customInstruction.isNotBlank()) { "Custom instruction must not be blank" }

        val systemPrompt = """You are an expert writing assistant.
Apply the following instruction to the provided transcript.
Return only the transformed text without commentary.

Instruction: $customInstruction""".trimIndent()

        Log.d(TAG, "Executing custom rewrite for transcript $transcriptId")
        val result = aiRepository.executePrompt(
            systemPrompt = systemPrompt,
            userPrompt = sourceText
        )

        return result.mapCatching { rewrittenText ->
            val version = TranscriptVersion(
                id = UUID.randomUUID().toString(),
                transcriptId = transcriptId,
                versionType = VersionType.Custom,
                createdAt = System.currentTimeMillis(),
                provider = "Groq",
                model = "llama-3.3-70b-versatile",
                content = rewrittenText,
                metadata = mapOf("custom_instruction" to customInstruction)
            )
            aiRepository.saveVersion(version)
            version
        }
    }

    companion object {
        private const val TAG = "RewriteService"
    }
}
