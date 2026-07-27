package com.echo.dictation.ai

import android.util.Log
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Applies AI rewrite transformations to a transcript version.
 *
 * Rewriting is always **on-demand** — it never happens automatically.
 * The user must explicitly trigger it via the "Rewrite" button in the UI.
 *
 * Supports:
 *  - Named presets via [PromptTemplateRepository]
 *  - Free-form custom prompts entered by the user
 *
 * The UI must communicate with this service only through [AIService].
 */
@Singleton
class RewriteService @Inject constructor(
    private val llm: LlmProvider,
) {

    /**
     * Rewrite [text] using the built-in preset identified by [templateId].
     *
     * @return [LlmResult.Success] with the rewritten text, or [LlmResult.Failure].
     * @throws IllegalArgumentException if [templateId] is not found in the library.
     */
    suspend fun rewriteWithPreset(text: String, templateId: String): LlmResult {
        val template = PromptTemplateRepository.findById(templateId)
            ?: return LlmResult.Failure(
                IllegalArgumentException("Unknown template id: $templateId"),
                "Rewrite preset '$templateId' not found",
            )

        Log.d(TAG, "Rewrite with preset '${template.title}' — input ${text.length} chars")
        return llm.complete(
            systemPrompt = template.systemPrompt,
            userPrompt   = text,
        )
    }

    /**
     * Rewrite [text] using the user's free-form [customInstruction].
     *
     * A generic wrapper system prompt is applied so the model stays focused on
     * the task and returns only the transformed text.
     *
     * @return [LlmResult.Success] with the transformed text, or [LlmResult.Failure].
     */
    suspend fun rewriteWithCustomPrompt(text: String, customInstruction: String): LlmResult {
        if (customInstruction.isBlank()) {
            return LlmResult.Failure(
                IllegalArgumentException("Custom prompt is blank"),
                "Please enter an instruction",
            )
        }

        val systemPrompt = """You are an expert writing assistant.
Apply the following instruction to the provided transcript.
Return only the transformed text — no explanations, no commentary.

Instruction: $customInstruction""".trimIndent()

        Log.d(TAG, "Rewrite with custom prompt — input ${text.length} chars")
        return llm.complete(
            systemPrompt = systemPrompt,
            userPrompt   = text,
        )
    }

    companion object {
        private const val TAG = "RewriteService"
    }
}
