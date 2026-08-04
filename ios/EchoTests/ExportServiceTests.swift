import XCTest
@testable import Echo

final class ExportServiceTests: XCTestCase {
    
    var exportService: ExportService!
    
    override func setUp() {
        super.setUp()
        exportService = ExportService()
    }
    
    func testExportPlainText() throws {
        let version = TranscriptVersion(text: "Sample exported text.", type: .original, title: "Original")
        let result = try exportService.export(version: version, format: .plainText)
        
        XCTAssertEqual(result.format, .plainText)
        XCTAssertTrue(result.filename.hasSuffix(".txt"))
        XCTAssertTrue(result.textContent.contains("Sample exported text."))
        XCTAssertFalse(result.dataContent.isEmpty)
    }
    
    func testExportMarkdown() throws {
        let version = TranscriptVersion(text: "## Header\nSample markdown text.", type: .preset(.summary), title: "Summary")
        let result = try exportService.export(version: version, format: .markdown)
        
        XCTAssertEqual(result.format, .markdown)
        XCTAssertTrue(result.filename.hasSuffix(".md"))
        XCTAssertTrue(result.textContent.contains("# Echo Transcript: Summary"))
        XCTAssertTrue(result.textContent.contains("Sample markdown text."))
    }
    
    func testExportPDF() throws {
        let version = TranscriptVersion(text: "Sample PDF document content.", type: .preset(.professional), title: "Professional")
        let result = try exportService.export(version: version, format: .pdf)
        
        XCTAssertEqual(result.format, .pdf)
        XCTAssertTrue(result.filename.hasSuffix(".pdf"))
        XCTAssertTrue(result.textContent.contains("%PDF-1.4"))
        XCTAssertFalse(result.dataContent.isEmpty)
    }
    
    func testExportDOCX() throws {
        let version = TranscriptVersion(text: "Sample Word DOCX document content.", type: .preset(.email), title: "Email")
        let result = try exportService.export(version: version, format: .docx)
        
        XCTAssertEqual(result.format, .docx)
        XCTAssertTrue(result.filename.hasSuffix(".docx"))
        XCTAssertTrue(result.textContent.contains("Sample Word DOCX document content."))
        XCTAssertFalse(result.dataContent.isEmpty)
    }
}
