package com.echo.dictation.presentation.export

import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import com.echo.dictation.domain.export.ExportFormat
import java.io.File

object ExportShareHelper {

    fun shareExportedFile(context: Context, file: File, format: ExportFormat) {
        val authority = "${context.packageName}.fileprovider"
        val contentUri = FileProvider.getUriForFile(context, authority, file)

        val mimeType = when (format) {
            ExportFormat.TXT -> "text/plain"
            ExportFormat.MARKDOWN -> "text/markdown"
            ExportFormat.PDF -> "application/pdf"
            ExportFormat.DOCX -> "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        }

        val shareIntent = Intent(Intent.ACTION_SEND).apply {
            type = mimeType
            putExtra(Intent.EXTRA_STREAM, contentUri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        val chooserIntent = Intent.createChooser(shareIntent, "Share ${file.name}")
        chooserIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(chooserIntent)
    }
}
