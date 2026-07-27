package com.echo.dictation.data.export.exporters

import com.echo.dictation.domain.ai.TranscriptVersion
import com.echo.dictation.domain.export.ExportOptions
import com.echo.dictation.domain.model.Transcription
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object MarkdownExporter {

    fun generateMarkdown(
        transcription: Transcription,
        version: TranscriptVersion?,
        options: ExportOptions
    ): String {
        val sb = StringBuilder()
        val formattedDate = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date(transcription.timestamp))
        val versionType = version?.versionType?.displayName ?: "Original"
        val content = version?.content ?: transcription.text

        if (options.includeTitle) {
            sb.appendLine("# Echo Transcript — $versionType")
            sb.appendLine()
        }

        if (options.includeDate || options.includeVersionType || options.includeModel || options.includeProvider) {
            sb.appendLine("> **Export Details**")
            if (options.includeDate) sb.appendLine("> - **Date:** $formattedDate")
            if (options.includeVersionType) sb.appendLine("> - **Version Type:** $versionType")
            if (options.includeModel) sb.appendLine("> - **STT Model:** `${transcription.model}`")
            if (options.includeProvider && version != null) sb.appendLine("> - **AI Engine:** ${version.provider} (`${version.model}`)")
            sb.appendLine()
        }

        if (options.includeMetadata && version?.metadata?.isNotEmpty() == true) {
            sb.appendLine("### Metadata")
            version.metadata.forEach { (k, v) -> sb.appendLine("- **$k:** `$v`") }
            sb.appendLine()
        }

        sb.appendLine("---")
        sb.appendLine()
        sb.appendLine(content)

        return sb.toString()
    }

    fun exportToFile(
        outputFile: File,
        transcription: Transcription,
        version: TranscriptVersion?,
        options: ExportOptions
    ): File {
        val mdContent = generateMarkdown(transcription, version, options)
        outputFile.writeText(mdContent, Charsets.UTF_8)
        return outputFile
    }
}
