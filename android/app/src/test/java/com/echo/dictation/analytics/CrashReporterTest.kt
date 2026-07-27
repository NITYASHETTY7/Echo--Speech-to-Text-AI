package com.echo.dictation.analytics

import com.echo.dictation.domain.analytics.CrashReporter
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class CrashReporterTest {

    class FakeCrashReporter : CrashReporter {
        val exceptions = mutableListOf<Pair<Throwable, String?>>()
        val customKeys = mutableMapOf<String, String>()

        override fun recordException(throwable: Throwable, reason: String?) {
            exceptions.add(throwable to reason)
        }

        override fun setCustomKey(key: String, value: String) {
            customKeys[key] = value
        }
    }

    @Test
    fun testRecordNonFatalException() {
        val reporter = FakeCrashReporter()
        val exception = IllegalStateException("Network timeout")

        reporter.setCustomKey("ai_provider", "Groq")
        reporter.recordException(exception, "Groq API Timeout")

        assertEquals(1, reporter.exceptions.size)
        assertEquals("Groq API Timeout", reporter.exceptions.first().second)
        assertEquals("Groq", reporter.customKeys["ai_provider"])
    }
}
