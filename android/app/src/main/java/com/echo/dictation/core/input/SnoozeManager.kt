package com.echo.dictation.core.input

import android.util.Log
import com.echo.dictation.data.local.AppPreferences
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Represents the current snooze state of the Floating Pill.
 */
sealed interface SnoozeState {
    /** Pill is not snoozed — normal visibility rules apply. */
    data object Off : SnoozeState

    /** Snoozed until [until] (epoch millis). Still active as long as `now < until`. */
    data class Until(val until: Long) : SnoozeState

    /** Snoozed indefinitely — only [SnoozeManager.resumeNow] clears it. */
    data object Indefinite : SnoozeState
}

/**
 * Encapsulates all Floating Pill snooze business logic.
 *
 * Responsibilities:
 *  - Persist the snooze expiry via [AppPreferences.snoozeUntil] (survives process death,
 *    app restarts, and device reboots — it's plain SharedPreferences on disk).
 *  - Expose [isSnoozedFlow] — a StateFlow that is `true` while snoozed and automatically
 *    flips back to `false` once the snooze duration elapses, without requiring the app
 *    to be reopened or any other event to occur. This works by combining the persisted
 *    expiry timestamp with a 1-second ticker while a finite snooze is pending.
 *  - Never touches Accessibility Service, overlay permission, or the foreground service —
 *    it only ever influences the pure UI-visibility decision made by
 *    [FocusAndKeyboardDetector].
 */
@Singleton
class SnoozeManager @Inject constructor(
    private val preferences: AppPreferences,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    /** Emits a tick every second, forever — cheap re-evaluation trigger for finite snoozes. */
    private val ticker = flow {
        while (true) {
            emit(Unit)
            delay(1_000L)
        }
    }

    /** Derived, always-current snooze state. Recomputed on every preference change and every tick. */
    val stateFlow: StateFlow<SnoozeState> =
        combine(preferences.snoozeUntilFlow, ticker) { until, _ -> toSnoozeState(until) }
            .distinctUntilChanged()
            .stateIn(scope, SharingStarted.Eagerly, toSnoozeState(preferences.snoozeUntil))

    /** True while the pill must stay hidden regardless of focus/keyboard/injection state. */
    val isSnoozedFlow: StateFlow<Boolean> =
        stateFlow
            .map { it != SnoozeState.Off }
            .distinctUntilChanged()
            .stateIn(scope, SharingStarted.Eagerly, isSnoozedNow())

    private fun toSnoozeState(until: Long): SnoozeState = when {
        until <= 0L                        -> SnoozeState.Off
        until == Long.MAX_VALUE            -> SnoozeState.Indefinite
        until > System.currentTimeMillis() -> SnoozeState.Until(until)
        else                                -> SnoozeState.Off // expired
    }

    private fun isSnoozedNow(): Boolean = toSnoozeState(preferences.snoozeUntil) != SnoozeState.Off

    /** Snooze the Floating Pill for [durationMs] starting now. */
    fun snoozeFor(durationMs: Long) {
        val until = System.currentTimeMillis() + durationMs
        preferences.snoozeUntil = until
        Log.d(TAG, "Snoozed for ${durationMs}ms → until=$until")
    }

    /**
     * Snooze using the fixed internal default duration ([DEFAULT_SNOOZE_DURATION_MS] — 30
     * minutes). This value is intentionally not user-configurable; there is no settings UI
     * or persisted preference for it, per product spec.
     */
    fun snoozeWithDefault() = snoozeFor(DEFAULT_SNOOZE_DURATION_MS)

    /** Snooze the Floating Pill until the user explicitly resumes it. */
    fun snoozeIndefinitely() {
        preferences.snoozeUntil = Long.MAX_VALUE
        Log.d(TAG, "Snoozed indefinitely")
    }

    /** Clears the snooze immediately, restoring normal Floating Pill behaviour. */
    fun resumeNow() {
        preferences.snoozeUntil = 0L
        Log.d(TAG, "Resumed — snooze cleared")
    }

    /** True if the pill is currently snoozed (persisted state, read synchronously). */
    fun isSnoozed(): Boolean = isSnoozedFlow.value

    companion object {
        private const val TAG = "SnoozeManager"

        /** Fixed, internal-only default snooze duration — 30 minutes. Not user-configurable. */
        const val DEFAULT_SNOOZE_DURATION_MS = 30 * 60 * 1000L
    }
}

