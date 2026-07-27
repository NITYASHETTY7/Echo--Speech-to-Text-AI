package com.echo.dictation.export

import com.echo.dictation.data.export.exporters.MarkdownExporter
import com.echo.dictation.data.export.exporters.TextExporter
import com.echo.dictation.domain.ai.TranscriptVersion
import com.echo.dictation.domain.ai.VersionType
import com.echo.dictation.domain.export.ExportOptions
import com.echo.dictation.domain.model.Transcription
import org.junit.Assert.assertTrue
import org.junit.Test

class TextAndMarkdownExporterTest {

    private val sampleTranscription = Transcription(
        id = "tx_1",
        text = "Original raw transcript content for testing.",
        timestamp = 1700000000000L,
        model = "whisper-large-v3-turbo",
        audioPath = null,
        userId = "user_1",
        synced = true
    )

    private val sampleVersion = TranscriptVersion(
        id = "ver_1",
        transcriptId = "tx_1",
        versionType = VersionType.Professional,
        createdAt = 1700000050000L,
        provider = "Groq",
        model = "llama-3.3-70b-versatile",
        content = "Professional polished version of the transcript.",
        metadata = mapOf("tone" to "Executive")
    )

    @Test
    fun testTextExporterGeneration() {
        val textOutput = TextExporter.generateText(sampleTranscription, sampleVersion, ExportOptions())
        assertTrue(textOutput.contains("ECHO TRANSCRIPTION EXPORT"))
        assertTrue(textOutput.contains("Professional polished version of the transcript."))
        assertTrue(textOutput.contains("Version Type: Professional"))
    }

    @Test
    fun testMarkdownExporterGeneration() {
        val mdOutput = MarkdownExporter.generateMarkdown(sampleTranscription, sampleVersion, ExportOptions())
        assertTrue(mdOutput.contains("# Echo Transcript — Professional"))
        assertTrue(mdOutput.contains("> - **Date:**"))
        assertTrue(mdOutput.contains("Professional polished version of the transcript."))
    }
}
