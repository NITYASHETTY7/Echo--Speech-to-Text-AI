package com.echo.dictation.domain.export

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object ExportFileNameGenerator {

    fun generateFileName(
        timestamp: Long,
        versionTypeName: String = "Original",
        format: ExportFormat
    ): String {
        val dateFormat = SimpleDateFormat("yyyy-MM-dd_HH-mm", Locale.US)
        val formattedDate = dateFormat.format(Date(timestamp))
        val sanitizedVersion = versionTypeName
            .replace("[^a-zA-Z0-9]".toRegex(), "")
            .ifBlank { "Original" }

        val extension = when (format) {
            ExportFormat.TXT -> "txt"
            ExportFormat.MARKDOWN -> "md"
            ExportFormat.PDF -> "pdf"
            ExportFormat.DOCX -> "docx"
        }

        return "Echo_Transcript_${formattedDate}_${sanitizedVersion}.$extension"
    }
}
