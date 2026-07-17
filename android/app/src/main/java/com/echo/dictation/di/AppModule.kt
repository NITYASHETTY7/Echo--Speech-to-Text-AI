package com.echo.dictation.di

import android.content.Context
import androidx.room.Room
import com.echo.dictation.BuildConfig
import com.echo.dictation.data.local.db.EchoDatabase
import com.echo.dictation.speech.GroqApi
import com.echo.dictation.speech.GroqApiKeyInterceptor
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import java.util.concurrent.TimeUnit
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object AppModule {

    // --- Room ---

    @Provides
    @Singleton
    fun db(@ApplicationContext c: Context): EchoDatabase =
        Room.databaseBuilder(c, EchoDatabase::class.java, "whisperflow.db").build()

    @Provides
    fun dao(db: EchoDatabase) = db.transcriptions()

    // --- Groq OkHttp client ---
    //
    // The Flask backend's AuthInterceptor (localhost Bearer token) is gone.
    // GroqApiKeyInterceptor replaces it: it injects "Authorization: Bearer <groq-key>"
    // read lazily from GroqApiKeyStore (EncryptedSharedPreferences) on every request.
    //
    // Timeouts mirror the old Flask client:
    //   connect  30 s - Groq's edge is fast but DNS + TLS add latency on mobile
    //   read    120 s - large audio files can take a while to process
    //   write   120 s - uploading a long recording over a slow connection

    @Provides
    @Singleton
    fun groqOkHttpClient(keyInterceptor: GroqApiKeyInterceptor): OkHttpClient =
        OkHttpClient.Builder()
            .addInterceptor(keyInterceptor)
            .addInterceptor(
                HttpLoggingInterceptor().apply {
                    level = if (BuildConfig.DEBUG)
                        HttpLoggingInterceptor.Level.BASIC
                    else
                        HttpLoggingInterceptor.Level.NONE
                }
            )
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(120, TimeUnit.SECONDS)
            .writeTimeout(120, TimeUnit.SECONDS)
            .build()

    // --- Groq Retrofit instance ---
    //
    // Hard-coded to https://api.groq.com/openai/v1/ - no BuildConfig field needed.
    // The old API_BASE_URL (LAN IP) has been removed from build.gradle.kts.

    @Provides
    @Singleton
    fun groqRetrofit(client: OkHttpClient): Retrofit =
        Retrofit.Builder()
            .baseUrl("https://api.groq.com/openai/v1/")
            .client(client)
            .addConverterFactory(GsonConverterFactory.create())
            .build()

    @Provides
    @Singleton
    fun groqApi(retrofit: Retrofit): GroqApi = retrofit.create(GroqApi::class.java)
}
