package com.echo.dictation.data.export

import android.content.Context
import android.util.Log
import com.echo.dictation.data.export.exporters.DocxExporter
import com.echo.dictation.data.export.exporters.MarkdownExporter
import com.echo.dictation.data.export.exporters.PdfExporter
import com.echo.dictation.data.export.exporters.TextExporter
import com.echo.dictation.data.local.db.ExportHistoryDao
import com.echo.dictation.data.local.db.toEntity
import com.echo.dictation.domain.ai.TranscriptVersion
import com.echo.dictation.domain.export.ExportFileNameGenerator
import com.echo.dictation.domain.export.ExportFormat
import com.echo.dictation.domain.export.ExportHistory
import com.echo.dictation.domain.export.ExportOptions
import com.echo.dictation.domain.export.ExportService
import com.echo.dictation.domain.model.Transcription
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ExportServiceImpl @Inject constructor(
    @ApplicationContext private val context: Context,
    private val exportHistoryDao: ExportHistoryDao,
) : ExportService {

    override suspend fun exportTranscription(
        transcription: Transcription,
        version: TranscriptVersion?,
        format: ExportFormat,
        options: ExportOptions
    ): Result<File> = withContext(Dispatchers.IO) {
        val exportId = UUID.randomUUID().toString()
        runCatching {
            val exportDir = File(context.cacheDir, "exports").apply { if (!exists()) mkdirs() }
            val versionTypeName = version?.versionType?.displayName ?: "Original"
            val fileName = ExportFileNameGenerator.generateFileName(
                timestamp = transcription.timestamp,
                versionTypeName = versionTypeName,
                format = format
            )
            val targetFile = File(exportDir, fileName)

            when (format) {
                ExportFormat.TXT -> TextExporter.exportToFile(targetFile, transcription, version, options)
                ExportFormat.MARKDOWN -> MarkdownExporter.exportToFile(targetFile, transcription, version, options)
                ExportFormat.PDF -> PdfExporter.exportToFile(targetFile, transcription, version, options)
                ExportFormat.DOCX -> DocxExporter.exportToFile(targetFile, transcription, version, options)
            }

            // Log export activity into Room DB
            val history = ExportHistory(
                id = exportId,
                transcriptId = transcription.id,
                versionId = version?.id,
                exportType = format,
                timestamp = System.currentTimeMillis(),
                destination = "LocalCache",
                success = true,
                filePath = targetFile.absolutePath
            )
            exportHistoryDao.insertExport(history.toEntity())
            Log.d(TAG, "Exported transcription ${transcription.id} as $format to ${targetFile.absolutePath}")

            targetFile
        }.onFailure { ex ->
            Log.e(TAG, "Failed to export transcription ${transcription.id} as $format: ${ex.message}", ex)
            val history = ExportHistory(
                id = exportId,
                transcriptId = transcription.id,
                versionId = version?.id,
                exportType = format,
                timestamp = System.currentTimeMillis(),
                destination = "LocalCache",
                success = false,
                filePath = null
            )
            runCatching { exportHistoryDao.insertExport(history.toEntity()) }
        }
    }

    companion object {
        private const val TAG = "ExportServiceImpl"
    }
}
