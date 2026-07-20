package com.echo.dictation.di

import com.echo.dictation.data.repository.SettingsRepositoryImpl
import com.echo.dictation.data.repository.TranscriptionRepositoryImpl
import com.echo.dictation.domain.repository.SettingsRepository
import com.echo.dictation.domain.repository.TranscriptionRepository
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

/**
 * Binds repository interfaces to their concrete implementations.
 *
 * Auth (OTP/Cognito flow) and its Flask backend have been removed.
 * All remote calls now go directly to Groq via GroqTranscriptionService.
 */
@Module
@InstallIn(SingletonComponent::class)
abstract class RepositoryModule {
    @Binds @Singleton abstract fun transcription(impl: TranscriptionRepositoryImpl): TranscriptionRepository
    @Binds @Singleton abstract fun settings(impl: SettingsRepositoryImpl): SettingsRepository
}
