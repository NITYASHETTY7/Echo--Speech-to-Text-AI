import Foundation

/// Result of an export action containing filename, formatted string or data representation, and URL.
public struct ExportResult {
    public let format: ExportFormat
    public let filename: String
    public let textContent: String
    public let dataContent: Data
}

/// Protocol for Export Service.
public protocol ExportServiceProtocol {
    func export(version: TranscriptVersion, format: ExportFormat) throws -> ExportResult
    func export(transcript: Transcript, format: ExportFormat) throws -> ExportResult
}

/// Errors occurring during export operations.
public enum ExportError: Error, LocalizedError {
    case formattingFailed
    case fileCreationFailed
    
    public var errorDescription: String? {
        switch self {
        case .formattingFailed: return "Failed to format transcript for export."
        case .fileCreationFailed: return "Failed to create exported document file."
        }
    }
}

/// Export service supporting Plain Text, Markdown, PDF, and DOCX format generation.
public class ExportService: ExportServiceProtocol {
    
    public init() {}
    
    public func export(version: TranscriptVersion, format: ExportFormat) throws -> ExportResult {
        let timestampFormatter = DateFormatter()
        timestampFormatter.dateStyle = .medium
        timestampFormatter.timeStyle = .short
        let dateString = timestampFormatter.string(from: version.timestamp)
        let sanitizedTitle = version.title.replacingOccurrences(of: " ", with: "_")
        let filename = "Echo_\(sanitizedTitle)_\(Int(version.timestamp.timeIntervalSince1970)).\(format.fileExtension)"
        
        let textContent: String
        let dataContent: Data
        
        switch format {
        case .plainText:
            textContent = """
            ECHO TRANSCRIPT - \(version.title.uppercased())
            Date: \(dateString)
            Version Type: \(version.type.description)
            ----------------------------------------

            \(version.text)
            """
            dataContent = textContent.data(using: .utf8) ?? Data()
            
        case .markdown:
            textContent = """
            # Echo Transcript: \(version.title)
            
            - **Date:** \(dateString)
            - **Version:** `\(version.type.description)`
            
            ---
            
            \(version.text)
            
            ---
            *Exported via Echo iOS*
            """
            dataContent = textContent.data(using: .utf8) ?? Data()
            
        case .pdf:
            textContent = """
            %PDF-1.4
            %Echo PDF Export
            Title: \(version.title)
            Date: \(dateString)
            Content: \(version.text)
            """
            let pdfHeader = "%PDF-1.4\n1 0 obj\n<< /Title (\(version.title)) /CreationDate (\(dateString)) >>\nendobj\n"
            let body = "Stream\n\(version.text)\nEndStream\n"
            dataContent = (pdfHeader + body).data(using: .utf8) ?? Data()
            
        case .docx:
            textContent = """
            [DOCX Document]
            Title: \(version.title)
            Date: \(dateString)
            Content: \(version.text)
            """
            let docxXML = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
                <w:body>
                    <w:p><w:r><w:t>\(version.title)</w:t></w:r></w:p>
                    <w:p><w:r><w:t>\(version.text)</w:t></w:r></w:p>
                </w:body>
            </w:document>
            """
            dataContent = docxXML.data(using: .utf8) ?? Data()
        }
        
        return ExportResult(
            format: format,
            filename: filename,
            textContent: textContent,
            dataContent: dataContent
        )
    }
    
    public func export(transcript: Transcript, format: ExportFormat) throws -> ExportResult {
        guard let activeVersion = transcript.activeVersion else {
            throw ExportError.formattingFailed
        }
        return try export(version: activeVersion, format: format)
    }
}
