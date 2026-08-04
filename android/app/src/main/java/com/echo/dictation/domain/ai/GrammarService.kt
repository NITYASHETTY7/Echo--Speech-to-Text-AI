package com.echo.dictation.domain.ai

import android.util.Log
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class GrammarService @Inject constructor(
    private val aiRepository: AIRepository,
    private val providerFactory: AIProviderFactory,
) {

    /**
     * Correct [rawTranscript] if enabled.
     * Always creates a NEW [TranscriptVersion] with [VersionType.GrammarCorrected]
     * without modifying the original.
     *
     * The provider and model recorded in the version reflect the ACTIVE provider at call-time,
     * not a hardcoded fallback.
     */
    suspend fun correctGrammar(
        transcriptId: String,
        rawTranscript: String,
        enabled: Boolean = true
    ): Result<TranscriptVersion?> {
        if (!enabled || rawTranscript.isBlank()) {
            Log.d(TAG, "Grammar correction disabled or text blank — skipping")
            return Result.success(null)
        }

        val providerName = safeProviderName()
        val modelName    = safeModelName()
        Log.d(TAG, "Executing grammar correction for transcript $transcriptId via $providerName/$modelName")

        val result = aiRepository.executePrompt(
            systemPrompt = SYSTEM_PROMPT,
            userPrompt   = rawTranscript,
        )

        return result.mapCatching { correctedText ->
            val version = TranscriptVersion(
                id           = UUID.randomUUID().toString(),
                transcriptId = transcriptId,
                versionType  = VersionType.GrammarCorrected,
                createdAt    = System.currentTimeMillis(),
                provider     = providerName,
                model        = modelName,
                content      = correctedText,
                metadata     = mapOf("source" to "grammar_service"),
            )
            aiRepository.saveVersion(version)
            version
        }.onFailure { ex ->
            Log.e(TAG, "Grammar correction failed for transcript $transcriptId: ${ex.message}", ex)
        }
    }

    private fun safeProviderName(): String =
        runCatching { providerFactory.currentProviderDisplayName() }.getOrDefault("Unknown")

    private fun safeModelName(): String =
        runCatching { providerFactory.getProvider().defaultModel }.getOrDefault("default")

    companion object {
        private const val TAG = "GrammarService"
        const val SYSTEM_PROMPT = """You are a grammar correction engine.

Fix ONLY the following in the text:
- Incorrect verb tense (e.g. "I have went" → "I went")
- Subject-verb agreement (e.g. "he don't" → "he doesn't", "me and john was" → "John and I were")
- Capitalization (sentences and proper nouns)
- Basic punctuation (periods, commas, question marks)
- Obvious spelling errors

DO NOT:
- Translate the text to another language. Keep the original language of the text.
- Summarize
- Add information not present in the original
- Change the vocabulary or tone
- Rewrite sentences for style
- Remove content

Return ONLY the corrected text with no commentary."""
    }
}
