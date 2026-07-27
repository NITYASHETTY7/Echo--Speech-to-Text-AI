package com.echo.dictation.domain.analytics

interface AnalyticsTracker {
    fun logEvent(name: String, params: Map<String, Any> = emptyMap())
}

object AnalyticsEvents {
    const val APP_OPEN = "app_open"
    const val RECORDING_STARTED = "recording_started"
    const val RECORDING_FINISHED = "recording_finished"
    const val TRANSCRIPTION_COMPLETED = "transcription_completed"
    const val GRAMMAR_GENERATED = "grammar_generated"
    const val REWRITE_GENERATED = "rewrite_generated"
    const val EXPORT_COMPLETED = "export_completed"
    const val SYNC_COMPLETED = "sync_completed"
    const val GOOGLE_LOGIN = "google_login"
    const val SETTINGS_CHANGED = "settings_changed"
}
