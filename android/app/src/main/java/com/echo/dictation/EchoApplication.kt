package com.echo.dictation

import android.app.Application
import android.util.Log
import androidx.hilt.work.HiltWorkerFactory
import androidx.work.Configuration
import com.echo.dictation.data.sync.SyncWorker
import com.echo.dictation.domain.session.SessionManager
import com.echo.dictation.domain.sync.SyncManager
import dagger.hilt.android.HiltAndroidApp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import timber.log.Timber
import javax.inject.Inject

/**
 * Application entry point.
 *
 * Implements [Configuration.Provider] so that WorkManager uses [HiltWorkerFactory],
 * which enables Hilt dependency injection inside [SyncWorker] (annotated @HiltWorker).
 *
 * ## Eager session + sync bootstrap
 *
 * [SessionManager] and [SyncManager] are injected here specifically to force Hilt to
 * CREATE them at process start.
 *
 * Previously the session was only ever populated by `AuthRepositoryImpl.init {}`, and
 * that singleton was only instantiated when `AuthViewModel` was constructed — which
 * happens exclusively on the ONBOARDING route and in SettingsScreen. After onboarding
 * completed, the app started at `Routes.MAIN`, so nothing ever instantiated it, the
 * session stayed null, and every cloud upload aborted at its null-user guard before
 * reaching Firestore. That is why the `transcripts` collection was never created.
 *
 * Injecting them here makes the bootstrap unconditional and screen-independent.
 */
@HiltAndroidApp
class EchoApplication : Application(), Configuration.Provider {

    @Inject
    lateinit var workerFactory: HiltWorkerFactory

    /** Injected to force eager creation — see class KDoc. */
    @Inject
    lateinit var sessionManager: SessionManager

    /** Injected to force eager creation — see class KDoc. */
    @Inject
    lateinit var syncManager: SyncManager

    private val appScope = CoroutineScope(Dispatchers.IO)

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setWorkerFactory(workerFactory)
            .build()

    override fun onCreate() {
        super.onCreate()
        if (BuildConfig.DEBUG) Timber.plant(Timber.DebugTree())

        // Diagnostic: prove which Firebase project the app is actually talking to.
        runCatching {
            val app = com.google.firebase.FirebaseApp.getInstance()
            Log.d(DIAG, "FirebaseApp name=${app.name} " +
                    "projectId=${app.options.projectId} " +
                    "applicationId=${app.options.applicationId}")
        }.onFailure { Log.e(DIAG, "FirebaseApp not initialised", it) }

        val uid = sessionManager.currentUser.value?.uid
        Log.d(DIAG, "EchoApplication.onCreate: session bootstrap uid=${uid ?: "NULL (signed out)"}")

        // Restore cloud history on every cold start for an already-signed-in user.
        // Safe to call unconditionally: it returns early when there is no user.
        if (uid != null) {
            appScope.launch {
                Log.d(DIAG, "EchoApplication: cold-start restore starting for uid=$uid")
                syncManager.restoreRecentHistory()
                    .onSuccess { Log.d(DIAG, "EchoApplication: cold-start restore SUCCESS") }
                    .onFailure { ex -> Log.e(DIAG, "EchoApplication: cold-start restore FAILED", ex) }
            }
        }

        // Schedule periodic cloud sync — WorkManager picks this up once it initialises
        runCatching { SyncWorker.schedulePeriodicSync(this) }
    }

    companion object {
        private const val DIAG = "CloudSync"
    }
}
