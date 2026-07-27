package com.echo.dictation

import android.app.Application
import androidx.hilt.work.HiltWorkerFactory
import androidx.work.Configuration
import com.echo.dictation.data.sync.SyncWorker
import dagger.hilt.android.HiltAndroidApp
import timber.log.Timber
import javax.inject.Inject

/**
 * Application entry point.
 *
 * Implements [Configuration.Provider] so that WorkManager uses [HiltWorkerFactory],
 * which enables Hilt dependency injection inside [SyncWorker] (annotated @HiltWorker).
 *
 * WorkManager must NOT be initialized elsewhere with [WorkManager.initialize] when
 * this pattern is used — Hilt/WorkManager integration handles initialization lazily.
 */
@HiltAndroidApp
class EchoApplication : Application(), Configuration.Provider {

    @Inject
    lateinit var workerFactory: HiltWorkerFactory

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setWorkerFactory(workerFactory)
            .build()

    override fun onCreate() {
        super.onCreate()
        if (BuildConfig.DEBUG) Timber.plant(Timber.DebugTree())

        // Schedule periodic cloud sync — WorkManager picks this up once it initialises
        runCatching { SyncWorker.schedulePeriodicSync(this) }
    }
}
