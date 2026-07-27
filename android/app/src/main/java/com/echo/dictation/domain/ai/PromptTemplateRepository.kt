package com.echo.dictation.domain.ai

import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class PromptTemplateRepository @Inject constructor() {

    private val templates = mutableMapOf<String, PromptTemplate>()

    init {
        // Register default templates
        registerDefaults()
    }

    private fun registerDefaults() {
        val defaults = listOf(
            PromptTemplate(
                id = "professional",
                title = "Professional",
                description = "Rewrite in clear, formal business language",
                category = PromptCategory.BUSINESS,
                systemPrompt = """You are a professional business writing editor.
Rewrite the transcript in clear, concise, and formal business language.
Preserve all facts, decisions, and names.
Return only the rewritten text without commentary.""".trimIndent(),
                targetVersionType = VersionType.Professional
            ),
            PromptTemplate(
                id = "summary",
                title = "Summary",
                description = "Concise summary capturing key points",
                category = PromptCategory.GENERAL,
                systemPrompt = """You are a professional summariser.
Write a concise, clear summary of the transcript.
Focus on the most important information, decisions, and outcomes.
Keep the summary to 3–5 sentences.
Return only the summary text.""".trimIndent(),
                targetVersionType = VersionType.Summary
            ),
            PromptTemplate(
                id = "meeting_notes",
                title = "Meeting Notes",
                description = "Format as structured meeting minutes",
                category = PromptCategory.PRODUCTIVITY,
                systemPrompt = """You are an expert meeting facilitator.
Convert the transcript into structured meeting notes with key discussion points, decisions made, and action items.
Return only the formatted meeting notes.""".trimIndent(),
                targetVersionType = VersionType.MeetingNotes
            ),
            PromptTemplate(
                id = "bullet_points",
                title = "Bullet Points",
                description = "Key information as a bulleted list",
                category = PromptCategory.GENERAL,
                systemPrompt = """You are a clear note-taker.
Extract the key information from the transcript and present it as a bulleted list.
Return only the bullet-point list.""".trimIndent(),
                targetVersionType = VersionType.BulletPoints
            ),
            PromptTemplate(
                id = "email",
                title = "Email",
                description = "Draft a professional email from transcript",
                category = PromptCategory.COMMUNICATION,
                systemPrompt = """You are an expert email writer.
Draft a professional email based on the content of the transcript.
Include a Subject line, greeting, clear body, and closing.
Return only the email text.""".trimIndent(),
                targetVersionType = VersionType.Email
            ),
            PromptTemplate(
                id = "action_items",
                title = "Action Items",
                description = "Extract all tasks and follow-ups",
                category = PromptCategory.PRODUCTIVITY,
                systemPrompt = """You are a project coordinator.
Identify and list every action item, task, and follow-up mentioned in the transcript.
Format as a numbered list.
Return only the action items.""".trimIndent(),
                targetVersionType = VersionType.Custom
            ),
            PromptTemplate(
                id = "translate",
                title = "Translate",
                description = "Translate into target language",
                category = PromptCategory.GENERAL,
                systemPrompt = """You are a professional translator.
Translate the transcript accurately into the target language requested by the user.
Return only the translated text.""".trimIndent(),
                targetVersionType = VersionType.Translation
            )
        )
        defaults.forEach { registerTemplate(it) }
    }

    fun registerTemplate(template: PromptTemplate) {
        templates[template.id] = template
    }

    fun getTemplate(id: String): PromptTemplate? = templates[id]

    fun getAllTemplates(): List<PromptTemplate> = templates.values.toList()

    fun getTemplatesByCategory(category: PromptCategory): List<PromptTemplate> =
        templates.values.filter { it.category == category }
}
