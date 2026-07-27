package com.echo.dictation.export

import com.echo.dictation.domain.export.ExportFileNameGenerator
import com.echo.dictation.domain.export.ExportFormat
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FileNameGeneratorTest {

    @Test
    fun testGenerateFileNameTxt() {
        val timestamp = 1700000000000L // Specific fixed date
        val fileName = ExportFileNameGenerator.generateFileName(timestamp, "Professional", ExportFormat.TXT)
        assertTrue("Filename should contain extension .txt", fileName.endsWith(".txt"))
        assertTrue("Filename should contain Professional tag", fileName.contains("Professional"))
    }

    @Test
    fun testGenerateFileNamePdf() {
        val timestamp = 1700000000000L
        val fileName = ExportFileNameGenerator.generateFileName(timestamp, "Meeting Notes", ExportFormat.PDF)
        assertTrue("Filename should contain extension .pdf", fileName.endsWith(".pdf"))
        assertTrue("Filename should contain MeetingNotes sanitized tag", fileName.contains("MeetingNotes"))
    }

    @Test
    fun testGenerateFileNameDocx() {
        val timestamp = 1700000000000L
        val fileName = ExportFileNameGenerator.generateFileName(timestamp, "Bullet Points", ExportFormat.DOCX)
        assertTrue("Filename should contain extension .docx", fileName.endsWith(".docx"))
    }
}
