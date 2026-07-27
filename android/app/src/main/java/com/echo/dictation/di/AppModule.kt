package com.echo.dictation.di

import android.content.Context
import android.util.Log
import androidx.room.Room
import com.echo.dictation.data.local.db.EchoDatabase
import com.echo.dictation.speech.provider.ProviderKeyStore
import com.echo.dictation.speech.provider.ProviderSettings
import com.echo.dictation.speech.provider.SpeechProviderFactory
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import java.util.concurrent.TimeUnit
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object AppModule {

    private const val TAG = "AppModule"

    // ── Room ──────────────────────────────────────────────────────────────────

    @Provides
    @Singleton
    fun db(@ApplicationContext c: Context): EchoDatabase =
        Room.databaseBuilder(c, EchoDatabase::class.java, "whisperflow.db")
            .fallbackToDestructiveMigration()
            .build()

    @Provides
    fun dao(db: EchoDatabase) = db.transcriptions()

    @Provides
    fun versionDao(db: EchoDatabase) = db.versions()

    @Provides
    fun aiJobDao(db: EchoDatabase) = db.aiJobs()

    @Provides
    fun exportHistoryDao(db: EchoDatabase) = db.exportHistory()

    // ── OkHttpClient ──────────────────────────────────────────────────────────

    @Provides
    @Singleton
    fun okHttpClient(): OkHttpClient {
        Log.d(TAG, "Building shared OkHttpClient")
        return OkHttpClient.Builder()
            .addInterceptor(
                HttpLoggingInterceptor { message ->
                    val safe = message
                        .replace(Regex("(?i)(authorization:\\s*)[^\\r\\n]+"), "$1[REDACTED]")
                        .replace(Regex("(?i)(x-goog-api-key:\\s*)[^\\r\\n]+"), "$1[REDACTED]")
                        .replace(Regex("(?i)(api-key:\\s*)[^\\r\\n]+"), "$1[REDACTED]")
                    Log.d("OkHttp", safe)
                }.apply { level = HttpLoggingInterceptor.Level.HEADERS }
            )
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(120, TimeUnit.SECONDS)
            .writeTimeout(120, TimeUnit.SECONDS)
            .build()
    }

    // ── Provider infrastructure ───────────────────────────────────────────────

    @Provides
    @Singleton
    fun speechProviderFactory(
        keyStore: ProviderKeyStore,
        settings: ProviderSettings,
        httpClient: OkHttpClient,
    ): SpeechProviderFactory = SpeechProviderFactory(keyStore, settings, httpClient)
}
