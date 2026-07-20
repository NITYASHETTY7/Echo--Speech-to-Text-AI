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
        Room.databaseBuilder(c, EchoDatabase::class.java, "whisperflow.db").build()

    @Provides
    fun dao(db: EchoDatabase) = db.transcriptions()

    // ── OkHttpClient ──────────────────────────────────────────────────────────
    //
    // A single shared OkHttpClient with no auth interceptor.
    // Authentication is added per-request by each SpeechProvider implementation
    // so that credential changes take effect immediately without rebuilding the client.
    //
    // Timeouts:
    //   connect  30 s — DNS + TLS on mobile
    //   read    120 s — large audio uploads / AssemblyAI polling
    //   write   120 s — uploading long recordings

    @Provides
    @Singleton
    fun okHttpClient(): OkHttpClient {
        Log.d(TAG, "Building shared OkHttpClient")
        return OkHttpClient.Builder()
            .addInterceptor(
                HttpLoggingInterceptor { message ->
                    // Redact any Authorization or api-key header values before logging
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
    //
    // ProviderKeyStore and ProviderSettings are @Inject-able singletons, so Hilt
    // constructs them automatically. SpeechProviderFactory is also @Inject-able,
    // but we explicitly provide it here so it receives the shared OkHttpClient.

    @Provides
    @Singleton
    fun speechProviderFactory(
        keyStore: ProviderKeyStore,
        settings: ProviderSettings,
        httpClient: OkHttpClient,
    ): SpeechProviderFactory = SpeechProviderFactory(keyStore, settings, httpClient)
}
