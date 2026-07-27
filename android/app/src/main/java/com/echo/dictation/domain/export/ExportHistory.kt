package com.echo.dictation.domain.export

data class ExportHistory(
    val id: String,
    val transcriptId: String,
    val versionId: String? = null,
    val exportType: ExportFormat,
    val timestamp: Long = System.currentTimeMillis(),
    val destination: String = "LocalFile",
    val success: Boolean = true,
    val filePath: String? = null
)
