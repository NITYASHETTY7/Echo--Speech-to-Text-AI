package com.echo.dictation.di

import com.echo.dictation.data.ai.AIRepositoryImpl
import com.echo.dictation.data.ai.GroqAIProvider
import com.echo.dictation.data.repository.AIJobRepositoryImpl
import com.echo.dictation.domain.ai.AIProvider
import com.echo.dictation.domain.ai.AIRepository
import com.echo.dictation.domain.repository.AIJobRepository
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
abstract class AiModule {

    @Binds
    @Singleton
    abstract fun bindAIProvider(impl: GroqAIProvider): AIProvider

    @Binds
    @Singleton
    abstract fun bindAIRepository(impl: AIRepositoryImpl): AIRepository

    @Binds
    @Singleton
    abstract fun bindAIJobRepository(impl: AIJobRepositoryImpl): AIJobRepository
}
