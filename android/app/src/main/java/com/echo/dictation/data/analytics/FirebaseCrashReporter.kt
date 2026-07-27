package com.echo.dictation.data.analytics

import android.util.Log
import com.echo.dictation.domain.analytics.CrashReporter
import com.google.firebase.crashlytics.FirebaseCrashlytics
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class FirebaseCrashReporter @Inject constructor() : CrashReporter {

    private val crashlytics: FirebaseCrashlytics?
        get() = runCatching { FirebaseCrashlytics.getInstance() }.getOrNull()

    override fun recordException(throwable: Throwable, reason: String?) {
        val fc = crashlytics ?: run {
            Log.e(TAG, "Crashlytics (unavailable) - Exception recorded: ${reason ?: throwable.message}", throwable)
            return
        }
        reason?.let { fc.log(it) }
        fc.recordException(throwable)
    }

    override fun setCustomKey(key: String, value: String) {
        crashlytics?.setCustomKey(key, value)
    }

    companion object {
        private const val TAG = "CrashReporter"
    }
}
