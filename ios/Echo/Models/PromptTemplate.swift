import Foundation

/// Prompt categories for categorizing templates in UI library.
public enum PromptCategory: String, Codable, CaseIterable, Identifiable {
    case general = "General"
    case business = "Business"
    case summary = "Summaries"
    case productivity = "Productivity"
    case custom = "Custom"
    
    public var id: String { rawValue }
}

/// Represents a reusable prompt template for rewriting transcriptions.
public struct PromptTemplate: Identifiable, Codable, Equatable, Hashable {
    public let id: UUID
    public let title: String
    public let description: String
    public let systemPrompt: String
    public let category: PromptCategory
    public let isBuiltIn: Bool
    
    public init(
        id: UUID = UUID(),
        title: String,
        description: String,
        systemPrompt: String,
        category: PromptCategory = .general,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.systemPrompt = systemPrompt
        self.category = category
        self.isBuiltIn = isBuiltIn
    }
    
    /// Default built-in prompt templates required for Feature 3.
    public static var defaultTemplates: [PromptTemplate] {
        [
            PromptTemplate(
                title: "Professional",
                description: "Refine language for formal business communication",
                systemPrompt: "Rewrite the following transcript into clear, professional, business-appropriate language. Preserve key facts.",
                category: .business,
                isBuiltIn: true
            ),
            PromptTemplate(
                title: "Summary",
                description: "Create a concise, executive-level summary",
                systemPrompt: "Provide a concise summary highlighting the core topic, context, and key outcomes of the following transcript.",
                category: .summary,
                isBuiltIn: true
            ),
            PromptTemplate(
                title: "Meeting Notes",
                description: "Organize transcript into structured meeting minutes",
                systemPrompt: "Format the following transcript as structured meeting notes with Attendees (if mentioned), Overview, Key Discussion Topics, and Decisions.",
                category: .productivity,
                isBuiltIn: true
            ),
            PromptTemplate(
                title: "Bullet Points",
                description: "Convert key information into clear bullet points",
                systemPrompt: "Extract the primary information from the transcript and present it as structured bullet points organized by topic.",
                category: .productivity,
                isBuiltIn: true
            ),
            PromptTemplate(
                title: "Email",
                description: "Draft a well-structured follow-up email",
                systemPrompt: "Draft a clear, professional email based on the contents of this transcript, including subject line and appropriate greeting.",
                category: .business,
                isBuiltIn: true
            ),
            PromptTemplate(
                title: "Action Items",
                description: "Extract concrete tasks and action items",
                systemPrompt: "Identify and list all action items, assignments, owners, and deadlines mentioned or implied in the transcript.",
                category: .productivity,
                isBuiltIn: true
            ),
            PromptTemplate(
                title: "Blog Style",
                description: "Transform spoken text into an engaging blog article",
                systemPrompt: "Rewrite this transcript as an engaging, reader-friendly blog post with catchy subheadings and smooth transitions.",
                category: .general,
                isBuiltIn: true
            ),
            PromptTemplate(
                title: "Social Media Post",
                description: "Craft short social media summary with key takeaways",
                systemPrompt: "Create a concise, engaging social media post (with hashtags) summarizing the main points of this transcript.",
                category: .general,
                isBuiltIn: true
            )
        ]
    }
}
