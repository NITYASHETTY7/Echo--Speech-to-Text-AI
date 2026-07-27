package com.echo.dictation.domain.ai

data class AIJob(
    val id: String,
    val transcriptId: String,
    val versionType: VersionType,
    val promptTemplateId: String? = null,
    val provider: String = "Groq",
    val model: String = "llama-3.3-70b-versatile",
    val status: JobStatus = JobStatus.PENDING,
    val retryCount: Int = 0,
    val createdAt: Long = System.currentTimeMillis(),
    val startedAt: Long? = null,
    val completedAt: Long? = null,
    val processingTimeMs: Long? = null,
    val errorMessage: String? = null,
)
