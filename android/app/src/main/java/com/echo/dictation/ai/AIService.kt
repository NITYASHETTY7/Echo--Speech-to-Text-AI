package com.echo.dictation.ai

import android.util.Log
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Single entry-point for all AI enhancement features.
 *
 * The UI communicates with **only** this service — no screen or ViewModel
 * calls [GroqLlmProvider], [GrammarCorrectionService], or [RewriteService]
 * directly. This decouples the LLM provider from the presentation layer so
 * future providers (OpenAI, Claude, Gemini, …) can be swapped without
 * touching any ViewModel or Composable.
 *
 * ## Responsibilities
 *  1. Post-transcription grammar correction (optional, Feature 1)
 *  2. On-demand preset rewrites (Feature 2)
 *  3. On-demand custom prompt rewrites (Feature 3)
 *  4. Serving the prompt library (Feature 4)
 *  5. Managing the in-session version store (Feature 5)
 */
@Singleton
class AIService @Inject constructor(
    private val grammarCorrection: GrammarCorrectionService,
    private val rewrite: RewriteService,
    private val versionStore: TranscriptVersionStore,
) {

    // ── Grammar correction toggle ─────────────────────────────────────────────

    var isGrammarCorrectionEnabled: Boolean
        get()  = grammarCorrection.enabled
        set(v) { grammarCorrection.enabled = v }

    // ── Post-transcription pipeline ───────────────────────────────────────────

    /**
     * Called immediately after the Speech-to-Text provider returns [rawText].
     *
     * Stores the original version, then optionally applies grammar correction.
     *
     * @return [AiEnhancementResult] describing what happened.
     */
    suspend fun onTranscriptionComplete(rawText: String): AiEnhancementResult {
        Log.d(TAG, "onTranscriptionComplete — rawText.length=${rawText.length} grammarEnabled=$isGrammarCorrectionEnabled")

        // Always store the original — it is never overwritten
        versionStore.startNewSession(rawText)

        if (!isGrammarCorrectionEnabled) {
            return AiEnhancementResult.NoEnhancement(rawText)
        }

        return when (val result = grammarCorrection.correct(rawText)) {
            is LlmResult.Success -> {
                val corrected = result.text
                if (corrected == rawText) {
                    // LLM returned the same text — no visible change
                    Log.d(TAG, "Grammar correction returned identical text")
                    AiEnhancementResult.NoEnhancement(rawText)
                } else {
                    val version = TranscriptVersion(
                        id    = "v_${System.currentTimeMillis()}_gc",
                        text  = corrected,
                        kind  = VersionKind.GrammarCorrected,
                        label = "Grammar Corrected",
                    )
                    versionStore.addVersion(version)
                    Log.d(TAG, "Grammar correction stored as version index=${versionStore.activeIndex.value}")
                    AiEnhancementResult.GrammarCorrected(rawText, corrected)
                }
            }
            is LlmResult.Failure -> {
                Log.w(TAG, "Grammar correction failed: ${result.message}")
                AiEnhancementResult.GrammarCorrectionFailed(rawText, result.message)
            }
        }
    }

    // ── On-demand rewrite ─────────────────────────────────────────────────────

    /**
     * Rewrite the currently active version using a named [templateId] from the
     * [PromptTemplateRepository].
     *
     * The original version is never modified. The new version is appended and
     * becomes the active version.
     */
    suspend fun rewriteWithPreset(templateId: String): AiEnhancementResult {
        val sourceText = versionStore.activeVersion?.text
            ?: return AiEnhancementResult.NoEnhancement("")

        val template = PromptTemplateRepository.findById(templateId)
            ?: return AiEnhancementResult.RewriteFailed("Unknown preset: $templateId")

        Log.d(TAG, "rewriteWithPreset '$templateId' — source ${sourceText.length} chars")

        return when (val result = rewrite.rewriteWithPreset(sourceText, templateId)) {
            is LlmResult.Success -> {
                val version = TranscriptVersion(
                    id    = "v_${System.currentTimeMillis()}_${templateId}",
                    text  = result.text,
                    kind  = VersionKind.Preset(templateId, template.title),
                    label = template.title,
                )
                versionStore.addVersion(version)
                AiEnhancementResult.Rewritten(result.text, template.title)
            }
            is LlmResult.Failure -> AiEnhancementResult.RewriteFailed(result.message)
        }
    }

    /**
     * Rewrite the currently active version using the user's free-form [instruction].
     */
    suspend fun rewriteWithCustomPrompt(instruction: String): AiEnhancementResult {
        val sourceText = versionStore.activeVersion?.text
            ?: return AiEnhancementResult.NoEnhancement("")

        Log.d(TAG, "rewriteWithCustomPrompt — source ${sourceText.length} chars")

        return when (val result = rewrite.rewriteWithCustomPrompt(sourceText, instruction)) {
            is LlmResult.Success -> {
                val version = TranscriptVersion(
                    id    = "v_${System.currentTimeMillis()}_custom",
                    text  = result.text,
                    kind  = VersionKind.Custom(instruction),
                    label = "Custom: ${instruction.take(24)}${if (instruction.length > 24) "…" else ""}",
                )
                versionStore.addVersion(version)
                AiEnhancementResult.Rewritten(result.text, "Custom")
            }
            is LlmResult.Failure -> AiEnhancementResult.RewriteFailed(result.message)
        }
    }

    // ── Prompt library ────────────────────────────────────────────────────────

    /** Returns all built-in prompt templates for display in the UI picker. */
    fun getPromptTemplates(): List<PromptTemplate> = PromptTemplateRepository.all

    // ── Version management ────────────────────────────────────────────────────

    /** The in-session version store, exposed read-only for ViewModels to observe. */
    val versionHistory: TranscriptVersionStore get() = versionStore

    companion object {
        private const val TAG = "AIService"
    }
}

// ─── Result types ─────────────────────────────────────────────────────────────

/** Describes the outcome of an AI enhancement operation. */
sealed interface AiEnhancementResult {
    /** No enhancement was applied (disabled, identical output, or empty input). */
    data class NoEnhancement(val text: String) : AiEnhancementResult

    /** Grammar correction was applied and produced a different result. */
    data class GrammarCorrected(val original: String, val corrected: String) : AiEnhancementResult

    /** Grammar correction was attempted but the LLM call failed. */
    data class GrammarCorrectionFailed(val original: String, val errorMessage: String) : AiEnhancementResult

    /** A rewrite operation succeeded. */
    data class Rewritten(val text: String, val label: String) : AiEnhancementResult

    /** A rewrite operation failed. */
    data class RewriteFailed(val errorMessage: String) : AiEnhancementResult
}
