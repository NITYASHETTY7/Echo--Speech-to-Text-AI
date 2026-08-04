import Foundation

/// Protocol defining AI Rewrite Service contract.
public protocol RewriteServiceProtocol {
    func rewrite(
        transcript: String,
        preset: VersionType.PresetType,
        config: LLMConfig
    ) async throws -> RewriteResult
    
    func rewriteCustom(
        transcript: String,
        customPrompt: String,
        config: LLMConfig
    ) async throws -> RewriteResult
    
    func rewriteWithTemplate(
        transcript: String,
        template: PromptTemplate,
        config: LLMConfig
    ) async throws -> RewriteResult
}

/// Service providing AI-powered text rewriting, presets, custom prompts, and template execution.
public class RewriteService: RewriteServiceProtocol {
    private let llmProviderService: LLMProviderServiceProtocol
    
    public init(llmProviderService: LLMProviderServiceProtocol = LLMProviderService()) {
        self.llmProviderService = llmProviderService
    }
    
    public func rewrite(
        transcript: String,
        preset: VersionType.PresetType,
        config: LLMConfig
    ) async throws -> RewriteResult {
        let systemPrompt = getPresetSystemPrompt(preset)
        let rewrittenText = try await llmProviderService.generateCompletion(
            prompt: transcript,
            systemPrompt: systemPrompt,
            config: config
        )
        
        let version = TranscriptVersion(
            text: rewrittenText,
            type: .preset(preset),
            title: preset.rawValue,
            metadata: ["preset": preset.rawValue, "provider": config.provider.rawValue]
        )
        
        return RewriteResult(
            originalText: transcript,
            rewrittenText: rewrittenText,
            promptUsed: systemPrompt,
            versionCreated: version
        )
    }
    
    public func rewriteCustom(
        transcript: String,
        customPrompt: String,
        config: LLMConfig
    ) async throws -> RewriteResult {
        let systemPrompt = "You are a professional writing assistant. Execute the following user instruction on the provided transcript without introducing false facts.\n\nInstruction: \(customPrompt)"
        
        let rewrittenText = try await llmProviderService.generateCompletion(
            prompt: transcript,
            systemPrompt: systemPrompt,
            config: config
        )
        
        let version = TranscriptVersion(
            text: rewrittenText,
            type: .custom(prompt: customPrompt),
            title: "Custom Prompt",
            metadata: ["customPrompt": customPrompt, "provider": config.provider.rawValue]
        )
        
        return RewriteResult(
            originalText: transcript,
            rewrittenText: rewrittenText,
            promptUsed: customPrompt,
            versionCreated: version
        )
    }
    
    public func rewriteWithTemplate(
        transcript: String,
        template: PromptTemplate,
        config: LLMConfig
    ) async throws -> RewriteResult {
        let rewrittenText = try await llmProviderService.generateCompletion(
            prompt: transcript,
            systemPrompt: template.systemPrompt,
            config: config
        )
        
        let version = TranscriptVersion(
            text: rewrittenText,
            type: .custom(prompt: template.title),
            title: template.title,
            metadata: ["templateId": template.id.uuidString, "templateTitle": template.title]
        )
        
        return RewriteResult(
            originalText: transcript,
            rewrittenText: rewrittenText,
            promptUsed: template.systemPrompt,
            versionCreated: version
        )
    }
    
    private func getPresetSystemPrompt(_ preset: VersionType.PresetType) -> String {
        switch preset {
        case .professional:
            return "Rewrite the following transcript into clear, professional, business-appropriate language. Preserve key facts and clarity."
        case .meetingNotes:
            return "Format the following transcript into clean, structured meeting notes with key points, topics, and conclusions."
        case .summary:
            return "Provide a concise summary highlighting the key context, topics, and conclusions from the transcript."
        case .bulletPoints:
            return "Convert the transcript into an organized set of clear, concise bullet points."
        case .email:
            return "Draft a well-structured follow-up email based on the contents of this transcript."
        case .blogStyle:
            return "Rewrite this transcript as an engaging, reader-friendly blog post with clear subheadings."
        case .socialMediaPost:
            return "Craft a concise social media post summarizing the main takeaways from this transcript."
        case .actionItems:
            return "Extract all action items, tasks, and follow-ups from the transcript as a clear checklist."
        }
    }
}
