package com.echo.dictation.domain.ai

enum class PromptCategory {
    GENERAL,
    BUSINESS,
    PRODUCTIVITY,
    COMMUNICATION,
}

data class PromptTemplate(
    val id: String,
    val title: String,
    val description: String,
    val category: PromptCategory,
    val systemPrompt: String,
    val targetVersionType: VersionType,
)
