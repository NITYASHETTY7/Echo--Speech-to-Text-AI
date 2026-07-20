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

@Module
@InstallIn(SingletonComponent::class)
abstract class RepositoryModule {
    @Binds @Singleton abstract fun transcription(impl: TranscriptionRepositoryImpl): TranscriptionRepository
    @Binds @Singleton abstract fun settings(impl: SettingsRepositoryImpl): SettingsRepository
}
