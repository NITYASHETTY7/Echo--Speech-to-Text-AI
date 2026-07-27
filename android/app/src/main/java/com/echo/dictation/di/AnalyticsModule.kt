package com.echo.dictation.di

import com.echo.dictation.data.analytics.FirebaseAnalyticsTracker
import com.echo.dictation.data.analytics.FirebaseCrashReporter
import com.echo.dictation.domain.analytics.AnalyticsTracker
import com.echo.dictation.domain.analytics.CrashReporter
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
abstract class AnalyticsModule {

    @Binds
    @Singleton
    abstract fun bindAnalyticsTracker(impl: FirebaseAnalyticsTracker): AnalyticsTracker

    @Binds
    @Singleton
    abstract fun bindCrashReporter(impl: FirebaseCrashReporter): CrashReporter
}
