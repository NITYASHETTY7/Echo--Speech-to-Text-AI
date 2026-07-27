package com.echo.dictation.analytics

import com.echo.dictation.domain.analytics.AnalyticsEvents
import com.echo.dictation.domain.analytics.AnalyticsTracker
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AnalyticsTrackerTest {

    class FakeAnalyticsTracker : AnalyticsTracker {
        val loggedEvents = mutableListOf<Pair<String, Map<String, Any>>>()

        override fun logEvent(name: String, params: Map<String, Any>) {
            loggedEvents.add(name to params)
        }
    }

    @Test
    fun testLogEventAnonymousOnly() {
        val fakeTracker = FakeAnalyticsTracker()

        fakeTracker.logEvent(
            AnalyticsEvents.TRANSCRIPTION_COMPLETED,
            mapOf("model" to "whisper-large-v3-turbo", "duration_sec" to 12)
        )

        assertEquals(1, fakeTracker.loggedEvents.size)
        val event = fakeTracker.loggedEvents.first()
        assertEquals(AnalyticsEvents.TRANSCRIPTION_COMPLETED, event.first)

        // Verify NO transcript text content is captured
        assertFalse(event.second.containsKey("text"))
        assertFalse(event.second.containsKey("transcript_content"))
        assertTrue(event.second.containsKey("model"))
    }
}
