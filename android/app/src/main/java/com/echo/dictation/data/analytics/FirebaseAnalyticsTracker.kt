package com.echo.dictation.data.analytics

import android.content.Context
import android.os.Bundle
import android.util.Log
import com.echo.dictation.domain.analytics.AnalyticsTracker
import com.google.firebase.analytics.FirebaseAnalytics
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class FirebaseAnalyticsTracker @Inject constructor(
    @ApplicationContext private val context: Context
) : AnalyticsTracker {

    private val analytics: FirebaseAnalytics?
        get() = runCatching { FirebaseAnalytics.getInstance(context) }.getOrNull()

    override fun logEvent(name: String, params: Map<String, Any>) {
        val fa = analytics ?: run {
            Log.d(TAG, "Analytics event skipped (Firebase unavailable): $name $params")
            return
        }

        val bundle = Bundle().apply {
            params.forEach { (k, v) ->
                when (v) {
                    is String -> putString(k, v)
                    is Int -> putInt(k, v)
                    is Long -> putLong(k, v)
                    is Boolean -> putBoolean(k, v)
                    is Double -> putDouble(k, v)
                    else -> putString(k, v.toString())
                }
            }
        }

        fa.logEvent(name, bundle)
        Log.d(TAG, "Logged analytics event: $name")
    }

    companion object {
        private const val TAG = "AnalyticsTracker"
    }
}
