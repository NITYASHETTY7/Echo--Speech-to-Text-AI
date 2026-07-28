package com.echo.dictation.di

import com.echo.dictation.data.ai.AIProviderFactoryImpl
import com.echo.dictation.data.ai.AIRepositoryImpl
import com.echo.dictation.data.repository.AIJobRepositoryImpl
import com.echo.dictation.domain.ai.AIProviderFactory
import com.echo.dictation.domain.ai.AIRepository
import com.echo.dictation.domain.repository.AIJobRepository
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

/**
 * Hilt module for AI dependencies.
 *
 * [AIProviderFactory] is the single injection point for AI text generation.
 * Swapping providers is handled entirely inside [AIProviderFactoryImpl] based on
 * [com.echo.dictation.speech.provider.ProviderSettings.selectedProvider].
 * No module changes are needed to add a new provider.
 */
@Module
@InstallIn(SingletonComponent::class)
abstract class AiModule {

    @Binds
    @Singleton
    abstract fun bindAIProviderFactory(impl: AIProviderFactoryImpl): AIProviderFactory

    @Binds
    @Singleton
    abstract fun bindAIRepository(impl: AIRepositoryImpl): AIRepository

    @Binds
    @Singleton
    abstract fun bindAIJobRepository(impl: AIJobRepositoryImpl): AIJobRepository
}
