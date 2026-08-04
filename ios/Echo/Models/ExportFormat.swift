import Foundation

/// Supported export formats for transcripts.
public enum ExportFormat: String, Codable, CaseIterable, Identifiable {
    case plainText = "Plain Text"
    case markdown = "Markdown"
    case pdf = "PDF"
    case docx = "DOCX"
    
    public var id: String { rawValue }
    
    public var fileExtension: String {
        switch self {
        case .plainText: return "txt"
        case .markdown: return "md"
        case .pdf: return "pdf"
        case .docx: return "docx"
        }
    }
    
    public var mimeType: String {
        switch self {
        case .plainText: return "text/plain"
        case .markdown: return "text/markdown"
        case .pdf: return "application/pdf"
        case .docx: return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        }
    }
    
    public var iconName: String {
        switch self {
        case .plainText: return "doc.text"
        case .markdown: return "text.badge.checkmark"
        case .pdf: return "doc.richtext"
        case .docx: return "doc.fill"
        }
    }
}
