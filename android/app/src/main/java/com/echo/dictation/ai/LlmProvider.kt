package com.echo.dictation.ai

/**
 * Contract for every LLM backend the AI pipeline can use.
 *
 * Adding a new provider (OpenAI, Claude, Gemini, …) requires only:
 *   1. Implement this interface.
 *   2. Register the implementation in [com.echo.dictation.di.AiModule].
 *
 * No ViewModels or repositories need to change.
 */
interface LlmProvider {

    /**
     * Human-readable name shown in logs / debug UI.
     * Example: "Groq (llama-3.3-70b-versatile)"
     */
    val name: String

    /**
     * Send [userPrompt] to the LLM, optionally prefixed with [systemPrompt].
     *
     * @param systemPrompt  Instruction that shapes how the model responds.
     *                      Pass null to omit a system message.
     * @param userPrompt    The text content to process.
     * @return [LlmResult.Success] with the trimmed model output on success,
     *         [LlmResult.Failure] wrapping the exception on any error.
     */
    suspend fun complete(systemPrompt: String?, userPrompt: String): LlmResult
}

/** Result type returned by every [LlmProvider]. */
sealed interface LlmResult {
    /** The model returned a non-blank response. */
    data class Success(val text: String) : LlmResult

    /** The request failed for any reason (network, auth, rate-limit, …). */
    data class Failure(val error: Throwable, val message: String = error.message ?: "Unknown error") : LlmResult
}
