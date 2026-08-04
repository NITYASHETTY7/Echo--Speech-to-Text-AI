import Foundation

/// Represents the type of transcript version generated.
public enum VersionType: Codable, Hashable, Equatable, CustomStringConvertible {
    case original
    case grammarCorrected
    case preset(PresetType)
    case custom(prompt: String)
    
    public enum PresetType: String, Codable, CaseIterable, Identifiable {
        case professional = "Professional"
        case meetingNotes = "Meeting Notes"
        case summary = "Summary"
        case bulletPoints = "Bullet Points"
        case email = "Email"
        case blogStyle = "Blog Style"
        case socialMediaPost = "Social Media Post"
        case actionItems = "Action Items"
        
        public var id: String { rawValue }
        
        public var description: String {
            switch self {
            case .professional: return "Rewrite in a professional and polished tone"
            case .meetingNotes: return "Format as clear meeting notes with key points"
            case .summary: return "Concise summary of the transcription"
            case .bulletPoints: return "Convert transcript into organized bullet points"
            case .email: return "Draft a well-structured email from transcript"
            case .blogStyle: return "Transform into an engaging blog post"
            case .socialMediaPost: return "Adapt into a social media post format"
            case .actionItems: return "Extract action items and key deliverables"
            }
        }
    }
    
    public var description: String {
        switch self {
        case .original:
            return "Original"
        case .grammarCorrected:
            return "Grammar Corrected"
        case .preset(let preset):
            return preset.rawValue
        case .custom(let prompt):
            return "Custom (\(prompt.prefix(20))...)"
        }
    }
    
    public var shortTitle: String {
        switch self {
        case .original:
            return "Original"
        case .grammarCorrected:
            return "Grammar"
        case .preset(let preset):
            return preset.rawValue
        case .custom:
            return "Custom"
        }
    }
}
