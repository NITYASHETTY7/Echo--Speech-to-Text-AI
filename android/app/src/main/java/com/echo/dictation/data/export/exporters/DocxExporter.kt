package com.echo.dictation.data.export.exporters

import com.echo.dictation.domain.ai.TranscriptVersion
import com.echo.dictation.domain.export.ExportOptions
import com.echo.dictation.domain.model.Transcription
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

object DocxExporter {

    fun exportToFile(
        outputFile: File,
        transcription: Transcription,
        version: TranscriptVersion?,
        options: ExportOptions
    ): File {
        val versionType = version?.versionType?.displayName ?: "Original"
        val content = version?.content ?: transcription.text
        val formattedDate = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date(transcription.timestamp))

        val contentXml = buildString {
            append("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>")
            append("<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">")
            append("<w:body>")

            if (options.includeTitle) {
                append("<w:p><w:pPr><w:pStyle w:val=\"Title\"/></w:pPr><w:r><w:t>Echo Transcript — ${escapeXml(versionType)}</w:t></w:r></w:p>")
            }

            if (options.includeDate || options.includeModel || options.includeProvider) {
                append("<w:p><w:r><w:rPr><w:b/></w:rPr><w:t>Export Details:</w:t></w:r></w:p>")
                if (options.includeDate) append("<w:p><w:r><w:t>Date: ${escapeXml(formattedDate)}</w:t></w:r></w:p>")
                if (options.includeModel) append("<w:p><w:r><w:t>Speech Model: ${escapeXml(transcription.model)}</w:t></w:r></w:p>")
                if (options.includeProvider && version != null) append("<w:p><w:r><w:t>AI Engine: ${escapeXml(version.provider)} (${escapeXml(version.model)})</w:t></w:r></w:p>")
                append("<w:p/>")
            }

            // Body paragraphs
            content.split("\n").forEach { paragraph ->
                append("<w:p><w:r><w:t xml:space=\"preserve\">${escapeXml(paragraph)}</w:t></w:r></w:p>")
            }

            append("</w:body></w:document>")
        }

        val contentTypesXml = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
    <Default Extension="xml" ContentType="application/xml"/>
    <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>"""

        val relsXml = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>"""

        val docRelsXml = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>"""

        ZipOutputStream(FileOutputStream(outputFile)).use { zos ->
            addZipEntry(zos, "[Content_Types].xml", contentTypesXml)
            addZipEntry(zos, "_rels/.rels", relsXml)
            addZipEntry(zos, "word/document.xml", contentXml)
            addZipEntry(zos, "word/_rels/document.xml.rels", docRelsXml)
        }

        return outputFile
    }

    private fun addZipEntry(zos: ZipOutputStream, entryName: String, content: String) {
        zos.putNextEntry(ZipEntry(entryName))
        zos.write(content.toByteArray(Charsets.UTF_8))
        zos.closeEntry()
    }

    private fun escapeXml(text: String): String = text
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("\"", "&quot;")
        .replace("'", "&apos;")
}
