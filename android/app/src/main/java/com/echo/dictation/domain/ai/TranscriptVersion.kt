package com.echo.dictation.domain.ai

data class TranscriptVersion(
    val id: String,
    val transcriptId: String,
    val versionType: VersionType,
    val createdAt: Long = System.currentTimeMillis(),
    val provider: String,
    val model: String,
    val content: String,
    val metadata: Map<String, String> = emptyMap(),
)
