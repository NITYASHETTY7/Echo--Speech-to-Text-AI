package com.echo.dictation.domain.analytics

interface CrashReporter {
    fun recordException(throwable: Throwable, reason: String? = null)
    fun setCustomKey(key: String, value: String)
}
