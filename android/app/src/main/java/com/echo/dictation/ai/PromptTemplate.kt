package com.echo.dictation.ai

/**
 * All prompt template categories.
 *
 * Adding a new category requires only adding an enum value here — no
 * business-logic changes are needed.
 */
enum class PromptCategory {
    GENERAL,
    BUSINESS,
    PRODUCTIVITY,
    COMMUNICATION,
}

/**
 * A reusable, immutable prompt template that can be applied to any transcript.
 *
 * @param id            Stable identifier used as a key in the prompt library.
 * @param title         Short user-facing label (e.g. "Meeting Notes").
 * @param description   One-line description shown in the UI picker.
 * @param systemPrompt  Instruction sent as the LLM system message.
 * @param category      Grouping for the library UI.
 */
data class PromptTemplate(
    val id: String,
    val title: String,
    val description: String,
    val systemPrompt: String,
    val category: PromptCategory,
)
