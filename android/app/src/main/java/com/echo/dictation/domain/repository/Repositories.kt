package com.echo.dictation.domain.repository

import com.echo.dictation.domain.model.AuthState
import com.echo.dictation.domain.model.User
import kotlinx.coroutines.flow.StateFlow

data class AuthConfig(val mode: String, val region: String, val userPoolId: String, val clientId: String)
interface AuthRepository { val authState: StateFlow<AuthState>; val currentUser: StateFlow<User?>; suspend fun config(): Result<AuthConfig>; suspend fun sendOtp(email: String): Result<String>; suspend fun verifyOtp(email: String, otp: String): Result<User>; suspend fun token(): String?; suspend fun logout() }
interface TranscriptionRepository { suspend fun transcribe(file: java.io.File, model: String): Result<com.echo.dictation.domain.model.Transcription>; fun history(limit: Int = 100): kotlinx.coroutines.flow.Flow<List<com.echo.dictation.domain.model.Transcription>>; suspend fun sync(): Result<Unit>; suspend fun delete(id: String) }
enum class ApiProvider { GROQ, OPENAI, BEDROCK }
interface SettingsRepository { val settings: StateFlow<com.echo.dictation.domain.model.AppSettings>; suspend fun saveKey(provider: ApiProvider, key: String): Result<Unit>; suspend fun test(provider: ApiProvider, key: String?): Result<Unit>; suspend fun updateLanguage(value: String); suspend fun updateRetention(value: Int); suspend fun updateGrammar(value: Boolean) }
