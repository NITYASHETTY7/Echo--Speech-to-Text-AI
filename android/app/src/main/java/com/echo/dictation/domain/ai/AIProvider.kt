package com.echo.dictation.domain.ai

/**
 * Interface contract for pluggable LLM providers (Groq, OpenAI, Gemini, Claude, etc.)
 */
interface AIProvider {
    val id: String
    val name: String
    val defaultModel: String

    suspend fun generateCompletion(
        systemPrompt: String?,
        userPrompt: String,
        modelOverride: String? = null
    ): Result<String>
}
