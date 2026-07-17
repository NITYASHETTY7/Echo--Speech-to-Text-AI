package com.echo.dictation

import android.app.Application
import com.echo.dictation.speech.GroqApiKeyStore
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.android.EntryPointAccessors
import dagger.hilt.components.SingletonComponent
import dagger.hilt.android.HiltAndroidApp
import timber.log.Timber

@HiltAndroidApp
class EchoApplication : Application() {

    @EntryPoint
    @InstallIn(SingletonComponent::class)
    interface AppEntryPoint {
        fun groqApiKeyStore(): GroqApiKeyStore
    }

    override fun onCreate() {
        super.onCreate()
        if (BuildConfig.DEBUG) Timber.plant(Timber.DebugTree())

        // Seed the Groq API key from the build-time constant (injected from
        // local.properties via BuildConfig). This runs once at startup so the
        // key is available before the first transcription attempt.
        // Only writes if the key is non-empty and not already stored, so a key
        // entered manually by the user is never silently overwritten.
        val buildKey = BuildConfig.GROQ_API_KEY
        if (buildKey.isNotBlank()) {
            val keyStore = EntryPointAccessors
                .fromApplication(this, AppEntryPoint::class.java)
                .groqApiKeyStore()
            if (!keyStore.isConfigured) {
                keyStore.apiKey = buildKey
            }
        }
    }
}
