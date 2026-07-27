package com.echo.dictation.domain.export

import com.echo.dictation.domain.ai.TranscriptVersion
import com.echo.dictation.domain.model.Transcription
import java.io.File

enum class ExportFormat { TXT, MARKDOWN, PDF, DOCX }

interface ExportService {
    suspend fun exportTranscription(
        transcription: Transcription,
        version: TranscriptVersion? = null,
        format: ExportFormat,
        options: ExportOptions = ExportOptions()
    ): Result<File>
}
