package com.echo.dictation.ai

import android.util.Log
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Applies optional AI grammar correction to a raw transcript.
 *
 * Grammar correction is optional and controlled by [enabled].
 * When disabled the service is a no-op and returns the raw text immediately —
 * the transcription pipeline continues unmodified.
 *
 * The UI must communicate with this service only through [AIService] —
 * nothing should call [GrammarCorrectionService] directly.
 */
@Singleton
class GrammarCorrectionService @Inject constructor(
    private val llm: LlmProvider,
) {

    /**
     * Whether grammar correction is currently active.
     * Toggled from [com.echo.dictation.data.local.AppPreferences].
     */
    var enabled: Boolean = false

    /**
     * Correct [rawTranscript] if [enabled] is true.
     *
     * @return [LlmResult.Success] with the corrected text when enabled and the call succeeds,
     *         [LlmResult.Success] with the original [rawTranscript] when disabled,
     *         [LlmResult.Failure] only when enabled and the LLM call fails.
     */
    suspend fun correct(rawTranscript: String): LlmResult {
        if (!enabled) {
            Log.d(TAG, "Grammar correction disabled — returning raw transcript")
            return LlmResult.Success(rawTranscript)
        }

        if (rawTranscript.isBlank()) {
            Log.d(TAG, "Empty transcript — skipping grammar correction")
            return LlmResult.Success(rawTranscript)
        }

        Log.d(TAG, "Grammar correction enabled — calling LLM (${rawTranscript.length} chars)")
        return llm.complete(
            systemPrompt = SYSTEM_PROMPT,
            userPrompt   = rawTranscript,
        )
    }

    companion object {
        private const val TAG = "GrammarCorrectionService"

        /** Exact prompt specified in the product requirements. */
        const val SYSTEM_PROMPT =
            "Correct grammar, punctuation, capitalization, spelling and formatting " +
            "without changing the meaning, wording or tone. " +
            "Do not translate the text to another language; keep the original spoken language. " +
            "Do not summarize. " +
            "Do not remove information. " +
            "Return only the corrected transcript."
    }
}
