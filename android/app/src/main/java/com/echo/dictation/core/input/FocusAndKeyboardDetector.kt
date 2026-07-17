package com.echo.dictation.core.input

import android.content.Context
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import com.echo.dictation.core.accessibility.TextInsertionAccessibilityService
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Detects when an editable text field is focused and the keyboard is visible.
 * Uses AccessibilityService to monitor focus changes efficiently.
 * Controls floating pill visibility via [shouldShowFloatingMic].
 */
@Singleton
class FocusAndKeyboardDetector @Inject constructor(
    @ApplicationContext private val context: Context
) {

    private val _shouldShowFloatingMic = MutableStateFlow(false)
    val shouldShowFloatingMic: StateFlow<Boolean> = _shouldShowFloatingMic.asStateFlow()

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

            val keyboardVisible = isKeyboardVisible()
            val shouldShow = node.isEditable && !node.isPassword && keyboardVisible
            Log.d(TAG, "Focus changed: editable=${node.isEditable} password=${node.isPassword} keyboard=$keyboardVisible → show=$shouldShow")
            updateVisibility(shouldShow)
        } catch (e: Exception) {
            Log.e(TAG, "Error checking focused field", e)
            updateVisibility(false)
        }
    }

    fun checkCurrentFocusState() {
        try {
            val service = TextInsertionAccessibilityService.instance ?: run {
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
            Log.d(TAG, "Focus state: editable=${focusedNode.isEditable} keyboard=$keyboardVisible → show=$shouldShow")
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
        if (_shouldShowFloatingMic.value != shouldShow) {
            Log.d(TAG, if (shouldShow) "Editable field focused" else "Editable field lost focus")
            _shouldShowFloatingMic.value = shouldShow
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
