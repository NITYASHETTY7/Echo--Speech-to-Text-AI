package com.echo.dictation.domain.repository

import com.echo.dictation.domain.model.AppSettings
import kotlinx.coroutines.flow.StateFlow

interface TranscriptionRepository {
    suspend fun transcribe(file: java.io.File, model: String): Result<com.echo.dictation.domain.model.Transcription>
    fun history(limit: Int = 100): kotlinx.coroutines.flow.Flow<List<com.echo.dictation.domain.model.Transcription>>
    suspend fun sync(): Result<Unit>
    suspend fun delete(id: String)
}

interface SettingsRepository {
    val settings: StateFlow<AppSettings>
    suspend fun updateLanguage(value: String)
    suspend fun updateRetention(value: Int)
    suspend fun updateGrammar(value: Boolean)
}
