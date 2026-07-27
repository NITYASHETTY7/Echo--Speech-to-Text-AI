package com.echo.dictation.ai

/**
 * Central repository of built-in [PromptTemplate]s.
 *
 * Design rule: adding a new template never requires changing any ViewModel,
 * service, or UI that consumes the library — only this object changes.
 */
object PromptTemplateRepository {

    val all: List<PromptTemplate> = listOf(
        PromptTemplate(
            id            = "professional",
            title         = "Professional",
            description   = "Rewrite in clear, formal business language",
            systemPrompt  = """You are a professional business writing editor.
Rewrite the transcript in clear, concise, and formal business language.
Preserve all facts, decisions, and names.
Return only the rewritten text without commentary.""".trimIndent(),
            category      = PromptCategory.BUSINESS,
        ),
        PromptTemplate(
            id            = "meeting_notes",
            title         = "Meeting Notes",
            description   = "Format as structured meeting minutes",
            systemPrompt  = """You are an expert meeting facilitator.
Convert the transcript into structured meeting notes with the following sections (only include sections that are relevant):
- **Overview** — one-sentence summary of the meeting purpose
- **Key Discussion Points** — bulleted list of main topics discussed
- **Decisions Made** — any decisions or agreements reached
- **Action Items** — tasks, owners, and deadlines if mentioned
- **Next Steps** — follow-up actions

Return only the formatted meeting notes.""".trimIndent(),
            category      = PromptCategory.PRODUCTIVITY,
        ),
        PromptTemplate(
            id            = "summary",
            title         = "Summary",
            description   = "Concise summary capturing key points",
            systemPrompt  = """You are a professional summariser.
Write a concise, clear summary of the transcript.
Focus on the most important information, decisions, and outcomes.
Keep the summary to 3–5 sentences.
Return only the summary text.""".trimIndent(),
            category      = PromptCategory.GENERAL,
        ),
        PromptTemplate(
            id            = "bullet_points",
            title         = "Bullet Points",
            description   = "Key information as a bulleted list",
            systemPrompt  = """You are a clear, organised note-taker.
Extract the key information from the transcript and present it as a bulleted list.
Group related points under short headings if appropriate.
Return only the bullet-point list — no introductory or closing sentences.""".trimIndent(),
            category      = PromptCategory.GENERAL,
        ),
        PromptTemplate(
            id            = "email",
            title         = "Email",
            description   = "Draft a professional email from the transcript",
            systemPrompt  = """You are an expert business email writer.
Draft a professional email based on the content of the transcript.
Include a concise Subject line, a greeting, a clear body, and a polite closing.
Preserve all specific details, names, and action items mentioned.
Return only the email text (Subject line first, then the body).""".trimIndent(),
            category      = PromptCategory.COMMUNICATION,
        ),
        PromptTemplate(
            id            = "action_items",
            title         = "Action Items",
            description   = "Extract all tasks and follow-ups",
            systemPrompt  = """You are a project coordinator.
Identify and list every action item, task, and follow-up mentioned or implied in the transcript.
For each item include: the task, the owner (if mentioned), and the deadline (if mentioned).
Format as a numbered list.
Return only the action-item list.""".trimIndent(),
            category      = PromptCategory.PRODUCTIVITY,
        ),
        PromptTemplate(
            id            = "translate",
            title         = "Translate",
            description   = "Translate to another language (specify in custom prompt)",
            systemPrompt  = """You are a professional translator.
Translate the transcript accurately into the language requested by the user.
Preserve the original meaning, tone, and formatting.
Return only the translated text.""".trimIndent(),
            category      = PromptCategory.GENERAL,
        ),
    )

    /** O(1) lookup by [PromptTemplate.id]. */
    private val byId: Map<String, PromptTemplate> = all.associateBy { it.id }

    fun findById(id: String): PromptTemplate? = byId[id]
}
