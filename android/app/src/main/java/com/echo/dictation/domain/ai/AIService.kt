package com.echo.dictation.domain.ai

import android.util.Log
import com.echo.dictation.domain.repository.AIJobRepository
import kotlinx.coroutines.flow.Flow
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AIService @Inject constructor(
    private val grammarService: GrammarService,
    private val rewriteService: RewriteService,
    private val promptRepository: PromptTemplateRepository,
    private val aiRepository: AIRepository,
    private val aiJobRepository: AIJobRepository,
) {

    /**
     * Runs the post-transcription AI pipeline synchronously and returns the
     * final text that should be displayed to the user.
     *
     * Pipeline:
     *   Raw text
     *     → (if grammarEnabled)  Grammar Correction  → saves [VersionType.GrammarCorrected]
     *     → (if autoEnhanceEnabled) Auto Enhance     → saves [VersionType.AutoEnhanced]
     *
     * Every intermediate version is persisted; only the last one is returned.
     * If both flags are off the raw text is returned unchanged.
     * If an AI step fails its version is not saved and the previous text is
     * forwarded to the next step (graceful degradation).
     */
    suspend fun processPostTranscription(
        transcriptId: String,
        rawText: String,
        grammarEnabled: Boolean = false,
        autoEnhanceEnabled: Boolean = false,
    ): String {
        if (rawText.isBlank()) return rawText
        if (!grammarEnabled && !autoEnhanceEnabled) return rawText

        Log.d(TAG, "Post-transcription pipeline for $transcriptId " +
                "(grammar=$grammarEnabled autoEnhance=$autoEnhanceEnabled)")

        // ── Step 1: Grammar Correction ────────────────────────────────────────
        var currentText = rawText
        if (grammarEnabled) {
            val jobId   = UUID.randomUUID().toString()
            val startAt = System.currentTimeMillis()
            val job = AIJob(
                id           = jobId,
                transcriptId = transcriptId,
                versionType  = VersionType.GrammarCorrected,
                status       = JobStatus.PROCESSING,
                startedAt    = startAt,
            )
            aiJobRepository.createJob(job)

            val result = grammarService.correctGrammar(transcriptId, rawText, enabled = true)
            val endAt  = System.currentTimeMillis()

            result.onSuccess { version ->
                aiJobRepository.updateJob(job.copy(
                    status = JobStatus.COMPLETED,
                    completedAt = endAt,
                    processingTimeMs = endAt - startAt,
                ))
                if (version != null) {
                    currentText = version.content
                    Log.d(TAG, "Grammar correction complete for $transcriptId")
                }
            }.onFailure { ex ->
                aiJobRepository.updateJob(job.copy(
                    status = JobStatus.FAILED,
                    completedAt = endAt,
                    errorMessage = ex.message ?: "Grammar correction failed",
                ))
                Log.w(TAG, "Grammar correction failed for $transcriptId — forwarding raw text", ex)
                // currentText stays as rawText; pipeline continues
            }
        }

        // ── Step 2: Auto Enhance ──────────────────────────────────────────────
        if (autoEnhanceEnabled) {
            val jobId   = UUID.randomUUID().toString()
            val startAt = System.currentTimeMillis()
            val job = AIJob(
                id           = jobId,
                transcriptId = transcriptId,
                versionType  = VersionType.AutoEnhanced,
                status       = JobStatus.PROCESSING,
                startedAt    = startAt,
            )
            aiJobRepository.createJob(job)

            val result = aiRepository.executePrompt(
                systemPrompt = AUTO_ENHANCE_SYSTEM_PROMPT,
                userPrompt   = currentText,
            )
            val endAt = System.currentTimeMillis()

            result.onSuccess { enhancedText ->
                val version = TranscriptVersion(
                    id           = UUID.randomUUID().toString(),
                    transcriptId = transcriptId,
                    versionType  = VersionType.AutoEnhanced,
                    createdAt    = System.currentTimeMillis(),
                    provider     = "Groq",
                    model        = "llama-3.3-70b-versatile",
                    content      = enhancedText,
                    metadata     = mapOf("source" to "auto_enhance"),
                )
                aiRepository.saveVersion(version)
                aiJobRepository.updateJob(job.copy(
                    status = JobStatus.COMPLETED,
                    completedAt = endAt,
                    processingTimeMs = endAt - startAt,
                ))
                currentText = enhancedText
                Log.d(TAG, "Auto Enhance complete for $transcriptId")
            }.onFailure { ex ->
                aiJobRepository.updateJob(job.copy(
                    status = JobStatus.FAILED,
                    completedAt = endAt,
                    errorMessage = ex.message ?: "Auto Enhance failed",
                ))
                Log.w(TAG, "Auto Enhance failed for $transcriptId — keeping previous text", ex)
                // currentText stays as grammar-corrected (or raw); returned below
            }
        }

        Log.d(TAG, "Pipeline complete for $transcriptId — final text length=${currentText.length}")
        return currentText
    }

    suspend fun applyRewritePreset(
        transcriptId: String,
        sourceText: String,
        templateId: String
    ): Result<TranscriptVersion> {
        val jobId = UUID.randomUUID().toString()
        val startTime = System.currentTimeMillis()
        val template = promptRepository.getTemplate(templateId)

        val job = AIJob(
            id = jobId,
            transcriptId = transcriptId,
            versionType = template?.targetVersionType ?: VersionType.Custom,
            promptTemplateId = templateId,
            status = JobStatus.PROCESSING,
            startedAt = startTime
        )
        aiJobRepository.createJob(job)

        val result = rewriteService.rewriteWithPreset(transcriptId, sourceText, templateId)
        val endTime = System.currentTimeMillis()

        result.onSuccess { version ->
            aiJobRepository.updateJob(
                job.copy(
                    status = JobStatus.COMPLETED,
                    completedAt = endTime,
                    processingTimeMs = endTime - startTime
                )
            )
        }.onFailure { ex ->
            aiJobRepository.updateJob(
                job.copy(
                    status = JobStatus.FAILED,
                    completedAt = endTime,
                    errorMessage = ex.message ?: "Rewrite failed"
                )
            )
        }
        return result
    }

    suspend fun applyCustomRewrite(
        transcriptId: String,
        sourceText: String,
        customInstruction: String
    ): Result<TranscriptVersion> {
        val jobId = UUID.randomUUID().toString()
        val startTime = System.currentTimeMillis()

        val job = AIJob(
            id = jobId,
            transcriptId = transcriptId,
            versionType = VersionType.Custom,
            status = JobStatus.PROCESSING,
            startedAt = startTime
        )
        aiJobRepository.createJob(job)

        val result = rewriteService.rewriteWithCustomPrompt(transcriptId, sourceText, customInstruction)
        val endTime = System.currentTimeMillis()

        result.onSuccess { version ->
            aiJobRepository.updateJob(
                job.copy(
                    status = JobStatus.COMPLETED,
                    completedAt = endTime,
                    processingTimeMs = endTime - startTime
                )
            )
        }.onFailure { ex ->
            aiJobRepository.updateJob(
                job.copy(
                    status = JobStatus.FAILED,
                    completedAt = endTime,
                    errorMessage = ex.message ?: "Custom rewrite failed"
                )
            )
        }
        return result
    }

    suspend fun applyTranslation(
        transcriptId: String,
        sourceText: String,
        targetLanguage: String,
    ): Result<TranscriptVersion> {
        val jobId   = UUID.randomUUID().toString()
        val startAt = System.currentTimeMillis()
        val job     = AIJob(
            id           = jobId,
            transcriptId = transcriptId,
            versionType  = VersionType.Translation,
            promptTemplateId = "translate",
            status       = JobStatus.PROCESSING,
            startedAt    = startAt,
        )
        aiJobRepository.createJob(job)

        val systemPrompt = """You are a professional translator.
Translate the following text accurately into $targetLanguage.
Preserve the meaning, tone, and structure of the original.
Return ONLY the translated text with no commentary or labels.""".trimIndent()

        val result = aiRepository.executePrompt(systemPrompt = systemPrompt, userPrompt = sourceText)
        val endAt  = System.currentTimeMillis()

        return result.mapCatching { translatedText ->
            val version = TranscriptVersion(
                id           = UUID.randomUUID().toString(),
                transcriptId = transcriptId,
                versionType  = VersionType.Translation,
                createdAt    = System.currentTimeMillis(),
                provider     = "Groq",
                model        = "llama-3.3-70b-versatile",
                content      = translatedText,
                metadata     = mapOf("target_language" to targetLanguage),
            )
            aiRepository.saveVersion(version)
            aiJobRepository.updateJob(job.copy(status = JobStatus.COMPLETED, completedAt = endAt, processingTimeMs = endAt - startAt))
            version
        }.onFailure { ex ->
            aiJobRepository.updateJob(job.copy(status = JobStatus.FAILED, completedAt = endAt, errorMessage = ex.message ?: "Translation failed"))
        }
    }

    fun getPromptTemplates(): List<PromptTemplate> =
        promptRepository.getAllTemplates()

    fun getTranscriptVersions(transcriptId: String): Flow<List<TranscriptVersion>> =
        aiRepository.getVersionsForTranscript(transcriptId)

    fun getLatestJobForTranscript(transcriptId: String): Flow<AIJob?> =
        aiJobRepository.observeLatestJobForTranscript(transcriptId)

    companion object {
        private const val TAG = "AIService"
        const val AUTO_ENHANCE_SYSTEM_PROMPT = """You are a professional writing enhancer.

Improve the readability, clarity, and natural flow of the transcript.
Make it sound polished and professional without changing the meaning.

Guidelines:
- Fix awkward sentence structures
- Improve word choice where it sounds unnatural
- Ensure logical flow between sentences
- Keep the same tone as the original (formal if formal, casual if casual)
- Do NOT summarize or remove content
- Do NOT add information not present

Return ONLY the enhanced text with no commentary."""
    }
}
