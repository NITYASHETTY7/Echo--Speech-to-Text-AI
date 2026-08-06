package com.echo.dictation.core.input

import android.content.Context
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import com.echo.dictation.core.accessibility.TextInsertionAccessibilityService
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Detects when an editable text field is focused and the keyboard is visible.
 * Uses AccessibilityService to monitor focus changes efficiently.
 * Controls floating pill visibility via [shouldShowFloatingMic].
 *
 * Visibility is gated on ALL of:
 *  1. Accessibility service connected (text injection available)
 *  2. Focused node is editable, non-password
 *  3. Keyboard (IME window) is visible
 *  4. Floating Pill is NOT snoozed ([SnoozeManager])
 *
 * The raw focus/keyboard/injection signal is tracked in [_rawShouldShow]; the
 * snooze gate is applied on top via [shouldShowFloatingMic], which is what
 * every visibility consumer (PillOverlayService) observes. This means a snooze
 * expiring while the app is running flips [shouldShowFloatingMic] back to the
 * raw value automatically, with no need to reopen the app or refocus a field.
 */
@Singleton
class FocusAndKeyboardDetector @Inject constructor(
    @ApplicationContext private val context: Context,
    private val snoozeManager: SnoozeManager,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    /** Raw signal from focus/keyboard/injection detection, ignoring snooze. */
    private val _rawShouldShow = MutableStateFlow(false)

    /**
     * Effective visibility signal — raw focus/keyboard/injection detection ANDed with
     * "not currently snoozed". This is the flow [com.echo.dictation.service.overlay.PillOverlayService]
     * observes to show/hide the overlay.
     */
    val shouldShowFloatingMic: StateFlow<Boolean> =
        combine(_rawShouldShow, snoozeManager.isSnoozedFlow) { rawShouldShow, snoozed ->
            rawShouldShow && !snoozed
        }.stateIn(scope, SharingStarted.Eagerly, _rawShouldShow.value && !snoozeManager.isSnoozed())

    private var lastFocusedNode: AccessibilityNodeInfo? = null

    fun onFocusChanged(event: AccessibilityEvent?) {
        if (event == null) return
        when (event.eventType) {
            AccessibilityEvent.TYPE_VIEW_FOCUSED ->
                checkIfEditableFieldFocused(event)
            AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED,
            AccessibilityEvent.TYPE_VIEW_TEXT_SELECTION_CHANGED,
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED,
            AccessibilityEvent.TYPE_WINDOWS_CHANGED ->
                checkCurrentFocusState()
        }
    }

    private fun checkIfEditableFieldFocused(event: AccessibilityEvent) {
        try {
            val node = event.source ?: run {
                updateVisibility(false)
                return
            }
            lastFocusedNode?.recycle()
            lastFocusedNode = node

            val injectionAvailable = TextInsertionAccessibilityService.instance != null
            val keyboardVisible = isKeyboardVisible()
            val shouldShow = injectionAvailable && node.isEditable && !node.isPassword && keyboardVisible
            Log.d(TAG, "Focus changed: editable=${node.isEditable} password=${node.isPassword} keyboard=$keyboardVisible injection=$injectionAvailable snoozed=${snoozeManager.isSnoozed()} → show=$shouldShow")
            updateVisibility(shouldShow)
        } catch (e: Exception) {
            Log.e(TAG, "Error checking focused field", e)
            updateVisibility(false)
        }
    }

    fun checkCurrentFocusState() {
        try {
            // Gate on injection availability first — if the AccessibilityService is not
            // connected there is no way to insert text, so the mic must not appear.
            val service = TextInsertionAccessibilityService.instance ?: run {
                Log.d(TAG, "Injection service not connected — hiding mic")
                updateVisibility(false)
                return
            }
            val rootNode = service.rootInActiveWindow ?: run {
                updateVisibility(false)
                return
            }
            val focusedNode = rootNode.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            lastFocusedNode?.recycle()
            lastFocusedNode = focusedNode

            if (focusedNode == null) {
                updateVisibility(false)
                return
            }

            val keyboardVisible = isKeyboardVisible()
            val shouldShow = focusedNode.isEditable && !focusedNode.isPassword && keyboardVisible
            Log.d(TAG, "Focus state: editable=${focusedNode.isEditable} keyboard=$keyboardVisible injection=true snoozed=${snoozeManager.isSnoozed()} → show=$shouldShow")
            updateVisibility(shouldShow)
        } catch (e: Exception) {
            Log.e(TAG, "Error checking current focus state", e)
            updateVisibility(false)
        }
    }

    private fun isKeyboardVisible(): Boolean {
        val service = TextInsertionAccessibilityService.instance ?: return false
        return runCatching {
            service.windows.any { window ->
                window.type == AccessibilityWindowInfo.TYPE_INPUT_METHOD
            }
        }.getOrDefault(false)
    }

    private fun updateVisibility(shouldShow: Boolean) {
        if (_rawShouldShow.value != shouldShow) {
            Log.d(TAG, if (shouldShow) "Editable field focused" else "Editable field lost focus")
            _rawShouldShow.value = shouldShow
        }
    }

    fun cleanup() {
        lastFocusedNode?.recycle()
        lastFocusedNode = null
    }

    companion object {
        private const val TAG = "FocusAndKeyboardDetector"

        /**
         * Static reference set by PillOverlayService at start.
         * Used by AccessibilityService for event forwarding since
         * AccessibilityService cannot use Hilt constructor injection.
         */
        @Volatile
        var instance: FocusAndKeyboardDetector? = null
            internal set
    }
}
