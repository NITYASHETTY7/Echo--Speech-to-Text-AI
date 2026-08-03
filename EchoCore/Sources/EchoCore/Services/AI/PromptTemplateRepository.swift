//
//  PromptTemplateRepository.swift
//  EchoCore
//
//  Central repository of built-in PromptTemplates.
//  All 7 system prompts match Android's PromptTemplateRepository exactly.
//  Adding a new template only requires changing this file.
//

import Foundation

// MARK: - PromptTemplateRepository

public final class PromptTemplateRepository: Sendable {

    // MARK: - Storage

    private let templates: [String: PromptTemplate]

    // MARK: - Init

    public init() {
        var map: [String: PromptTemplate] = [:]
        for t in PromptTemplateRepository.defaults { map[t.id] = t }
        self.templates = map
    }

    // MARK: - Queries

    public func getTemplate(_ id: String) -> PromptTemplate? { templates[id] }
    public func getAllTemplates() -> [PromptTemplate] { Array(templates.values) }
    public func getTemplates(for category: PromptCategory) -> [PromptTemplate] {
        templates.values.filter { $0.category == category }
    }

    // MARK: - Default templates (exact Android parity)

    public static let defaults: [PromptTemplate] = [

        PromptTemplate(
            id: "professional",
            title: "Professional",
            description: "Rewrite in clear, formal business language",
            category: .business,
            systemPrompt: """
You are a professional business writing editor.
Rewrite the transcript in clear, concise, and formal business language.
Preserve all facts, decisions, and names.
Return only the rewritten text without commentary.
""",
            targetVersionType: .professional
        ),

        PromptTemplate(
            id: "summary",
            title: "Summary",
            description: "Concise summary capturing key points",
            category: .general,
            systemPrompt: """
You are a professional summariser.
Write a concise, clear summary of the transcript.
Focus on the most important information, decisions, and outcomes.
Keep the summary to 3–5 sentences.
Return only the summary text.
""",
            targetVersionType: .summary
        ),

        PromptTemplate(
            id: "meeting_notes",
            title: "Meeting Notes",
            description: "Format as structured meeting minutes",
            category: .productivity,
            systemPrompt: """
You are an expert meeting facilitator.
Convert the transcript into structured meeting notes with key discussion points, decisions made, and action items.
Return only the formatted meeting notes.
""",
            targetVersionType: .meetingNotes
        ),

        PromptTemplate(
            id: "bullet_points",
            title: "Bullet Points",
            description: "Key information as a bulleted list",
            category: .general,
            systemPrompt: """
You are a clear note-taker.
Extract the key information from the transcript and present it as a bulleted list.
Return only the bullet-point list.
""",
            targetVersionType: .bulletPoints
        ),

        PromptTemplate(
            id: "email",
            title: "Email",
            description: "Draft a professional email from transcript",
            category: .communication,
            systemPrompt: """
You are an expert email writer.
Draft a professional email based on the content of the transcript.
Include a Subject line, greeting, clear body, and closing.
Return only the email text.
""",
            targetVersionType: .email
        ),

        PromptTemplate(
            id: "action_items",
            title: "Action Items",
            description: "Extract all tasks and follow-ups",
            category: .productivity,
            systemPrompt: """
You are a project coordinator.
Identify and list every action item, task, and follow-up mentioned in the transcript.
Format as a numbered list.
Return only the action items.
""",
            // Mirrors Android: action_items → VersionType.Custom
            targetVersionType: .custom
        ),

        PromptTemplate(
            id: "translate",
            title: "Translate",
            description: "Translate into target language",
            category: .general,
            systemPrompt: """
You are a professional translator.
Translate the transcript accurately into the target language requested by the user.
Return only the translated text.
""",
            targetVersionType: .translation
        ),
    ]

    // MARK: - Special system prompts (used by AIService directly)

    /// Grammar correction system prompt — matches Android's GrammarService.SYSTEM_PROMPT exactly.
    /// Grammar correction is language-neutral; it fixes the text in whatever language it is in.
    public static let grammarCorrectionSystemPrompt = """
You are a grammar correction engine.

Fix ONLY the following in the text:
- Incorrect verb tense (e.g. "I have went" → "I went")
- Subject-verb agreement (e.g. "he don't" → "he doesn't", "me and john was" → "John and I were")
- Capitalization (sentences and proper nouns)
- Basic punctuation (periods, commas, question marks)
- Obvious spelling errors

DO NOT:
- Summarize
- Add information not present in the original
- Change the vocabulary or tone
- Rewrite sentences for style
- Remove content
- Translate or change the language

CRITICAL: Your response MUST be in the SAME LANGUAGE as the input text.
If the input is Korean, respond in Korean.
If the input is Japanese, respond in Japanese.
If the input is Hindi, respond in Hindi.
Never translate the text into any other language.

Return ONLY the corrected text with no commentary.
"""

    /// Auto-enhance system prompt — matches Android's AIService.AUTO_ENHANCE_SYSTEM_PROMPT exactly.
    public static let autoEnhanceSystemPrompt = """
You are a professional writing enhancer.

Improve the readability, clarity, and natural flow of the transcript.
Make it sound polished and professional without changing the meaning.

Guidelines:
- Fix awkward sentence structures
- Improve word choice where it sounds unnatural
- Ensure logical flow between sentences
- Keep the same tone as the original (formal if formal, casual if casual)
- Do NOT summarize or remove content
- Do NOT add information not present

CRITICAL: Your response MUST be in the SAME LANGUAGE as the input text.
If the input is Korean, respond in Korean.
If the input is Japanese, respond in Japanese.
If the input is Hindi, respond in Hindi.
Never translate the text into any other language.

Return ONLY the enhanced text with no commentary.
"""

    // MARK: - Output-language aware prompt builders

    /// Returns a system prompt for a preset template with an unconditional
    /// output-language directive appended.
    ///
    /// The directive is always included — even for English — so the model never
    /// falls back to the input transcript's language.
    public static func presetSystemPrompt(
        template: PromptTemplate,
        outputLanguage: String
    ) -> String {
        let lang = outputLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        let effective = lang.isEmpty ? "English" : lang
        return """
\(template.systemPrompt)

OUTPUT LANGUAGE: \(effective).
Regardless of the language of the input text, you MUST write your entire response in \(effective).
Do not use any other language.
"""
    }

    /// Custom rewrite system prompt with unconditional output-language directive.
    public static func customRewriteSystemPrompt(
        instruction: String,
        outputLanguage: String = "English"
    ) -> String {
        let lang = outputLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        let effective = lang.isEmpty ? "English" : lang
        return """
You are an expert writing assistant.
Apply the following instruction to the provided transcript.
Return only the transformed text without any commentary or explanation.

Instruction: \(instruction)

OUTPUT LANGUAGE: \(effective).
Regardless of the language of the input text, you MUST write your entire response in \(effective).
Do not use any other language.
"""
    }

    /// Translation system prompt.
    /// `targetLanguage` IS the output language — named consistently for clarity.
    public static func translationSystemPrompt(targetLanguage: String) -> String {
        let lang = targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        let effective = lang.isEmpty ? "English" : lang
        return """
You are a professional translator.
Translate the following text accurately into \(effective).
Preserve the meaning, tone, and structure of the original.

OUTPUT LANGUAGE: \(effective).
Return ONLY the translated text in \(effective) with no commentary, labels, or explanation.
"""
    }
}
