package com.echo.dictation.domain.model

data class Transcription(
    val id: String,
    val text: String,
    val timestamp: Long,
    val model: String,
    val audioPath: String? = null,
    val userId: String,
    val synced: Boolean = false,
)

data class AppSettings(
    val language: String = "en",
    val model: String = "whisper-large-v3-turbo",
    val retentionDays: Int = 30,
    val grammarEnabled: Boolean = true,
    val theme: String = "system",
    val autoStart: Boolean = false,
    val providerConfigured: Map<String, Boolean> = emptyMap(),
)
