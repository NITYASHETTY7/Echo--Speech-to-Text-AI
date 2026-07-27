package com.echo.dictation.domain.export

data class ExportOptions(
    val includeTitle: Boolean = true,
    val includeDate: Boolean = true,
    val includeProvider: Boolean = true,
    val includeModel: Boolean = true,
    val includeVersionType: Boolean = true,
    val includeMetadata: Boolean = true,
)
