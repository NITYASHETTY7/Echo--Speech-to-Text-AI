package com.echo.dictation.core.accessibility

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Bundle
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Toast
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Helper class for inserting text into the currently focused text field.
 * Uses AccessibilityService APIs when available, with clipboard fallback.
 */
@Singleton
class TextInsertionHelper @Inject constructor(
    @ApplicationContext private val context: Context
) {
    /**
     * Inserts text into the currently focused editable field. Clipboard is used as the
     * terminal fallback only when AccessibilityService insertion is unavailable or fails.
     */
    fun insertText(text: String, showToast: Boolean = true): Boolean {
        return insertTextIntoNode(text, targetNode = null, showToast = showToast)
    }

    /**
     * Inserts text into [targetNode] if provided (pre-captured at tap time), or discovers
     * the focused node live. Clipboard is used only if both methods fail.
     */
    fun insertTextIntoNode(
        text: String,
        targetNode: AccessibilityNodeInfo?,
        showToast: Boolean = true
    ): Boolean {
        Log.d(TAG, "▶ insertTextIntoNode text=${text.take(40)} targetNode=${if (targetNode != null) "pre-captured" else "null/live"}")

        val accessibilityService = TextInsertionAccessibilityService.instance
        Log.d(TAG, "▶ [0] AccessibilityService.instance = ${if (accessibilityService != null) "CONNECTED (${accessibilityService.javaClass.simpleName})" else "NULL — service not connected or was killed"}")
        if (accessibilityService != null) {
            val node = targetNode ?: accessibilityService.lastEditableNode
            val inserted = performInsertion(accessibilityService, node, text)
            if (inserted) {
                Log.d(TAG, "Direct insertion succeeded")
                if (showToast) {
                    Toast.makeText(context, "Text inserted", Toast.LENGTH_SHORT).show()
                }
                return true
            }
        }

        Log.d(TAG, "Clipboard fallback used: focused cursor insertion failed or unavailable")
        copyToClipboard(text)
        if (showToast) {
            Toast.makeText(context, "Transcription copied to clipboard", Toast.LENGTH_SHORT).show()
        }
        return false
    }

    fun showNoSpeechDetected() {
        Toast.makeText(context, "No speech detected. Please try again.", Toast.LENGTH_SHORT).show()
    }

    private fun performInsertion(
        service: AccessibilityService,
        preCapuredNode: AccessibilityNodeInfo?,
        text: String
    ): Boolean {
        return try {
            Log.d(TAG, "▶ [1] service=${service.javaClass.simpleName} preCaptured=${preCapuredNode?.let { describeNode(it) } ?: "null"}")

            // Use the pre-captured node when available — it was snapshotted at tap time,
            // before the network call and before the overlay tap cleared FOCUS_INPUT.
            val focusedNode: AccessibilityNodeInfo? = if (preCapuredNode != null && preCapuredNode.isEditable) {
                preCapuredNode.refresh()
                if (preCapuredNode.isEditable) preCapuredNode else null
            } else {
                val root = service.rootInActiveWindow
                Log.d(TAG, "▶ [2] rootInActiveWindow = ${if (root != null) "NOT NULL (pkg=${root.packageName})" else "NULL"}")
                if (root == null) {
                    Log.d(TAG, "✗ [2] rootInActiveWindow is null → clipboard fallback")
                    return false
                }
                val inputNode = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
                val accessNode = root.findFocus(AccessibilityNodeInfo.FOCUS_ACCESSIBILITY)
                Log.d(TAG, "▶ [3] FOCUS_INPUT    = ${inputNode?.let { describeNode(it) } ?: "null"}")
                Log.d(TAG, "▶ [3] FOCUS_ACCESSIBILITY = ${accessNode?.let { describeNode(it) } ?: "null"}")
                listOfNotNull(inputNode, accessNode).firstOrNull { it.isEditable }
            }

            if (focusedNode == null) {
                Log.d(TAG, "✗ [3] No editable node found → clipboard fallback")
                return false
            }
            Log.d(TAG, "▶ [4] Using: ${describeNode(focusedNode)}")

            val currentText = focusedNode.text?.toString().orEmpty()
            val selectionStart = focusedNode.textSelectionStart
            val selectionEnd = focusedNode.textSelectionEnd
            Log.d(TAG, "▶ [5] len=${currentText.length} sel=[$selectionStart,$selectionEnd]")

            if (selectionStart < 0 || selectionEnd < 0) {
                Log.d(TAG, "▶ [5] selection unavailable; trying ACTION_PASTE at native cursor")
                val r = tryPasteAction(focusedNode, text)
                Log.d(TAG, "${if (r) "✓ [5] PASTE succeeded" else "✗ [5] PASTE failed → clipboard fallback"}")
                return r
            }

            val cursor = maxOf(selectionStart, selectionEnd).coerceIn(0, currentText.length)
            val updatedText = currentText.substring(0, cursor) + text + currentText.substring(cursor)
            val newCursor = cursor + text.length
            Log.d(TAG, "▶ [6] ACTION_SET_TEXT cursor=$cursor updatedLen=${updatedText.length}")

            val setTextResult = focusedNode.performAction(
                AccessibilityNodeInfo.ACTION_SET_TEXT,
                Bundle().apply {
                    putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, updatedText)
                }
            )
            Log.d(TAG, "${if (setTextResult) "✓ [6] ACTION_SET_TEXT succeeded" else "✗ [6] ACTION_SET_TEXT false; trying paste"}")

            if (setTextResult) {
                // Reacquire after text changed so cursor lands at the right position.
                val fresh = service.rootInActiveWindow?.let {
                    listOfNotNull(
                        it.findFocus(AccessibilityNodeInfo.FOCUS_INPUT),
                        it.findFocus(AccessibilityNodeInfo.FOCUS_ACCESSIBILITY)
                    ).firstOrNull { n -> n.isEditable }
                } ?: focusedNode
                setCursor(fresh, newCursor)
                return true
            }

            Log.d(TAG, "▶ [7] ACTION_SET_SELECTION=$cursor then ACTION_PASTE")
            setCursor(focusedNode, cursor)
            val pasteResult = tryPasteAction(focusedNode, text)
            Log.d(TAG, "${if (pasteResult) "✓ [7] PASTE succeeded" else "✗ [7] PASTE failed → clipboard fallback"}")
            if (!pasteResult) return false

            val fresh = service.rootInActiveWindow?.let {
                listOfNotNull(
                    it.findFocus(AccessibilityNodeInfo.FOCUS_INPUT),
                    it.findFocus(AccessibilityNodeInfo.FOCUS_ACCESSIBILITY)
                ).firstOrNull { n -> n.isEditable }
            } ?: focusedNode
            setCursor(fresh, newCursor)
            return true
        } catch (e: Exception) {
            Log.e(TAG, "✗ [EXCEPTION] ${e.javaClass.simpleName}: ${e.message}", e)
            false
        }
    }

    private fun describeNode(node: AccessibilityNodeInfo): String =
        "pkg=${node.packageName} cls=${node.className} " +
            "isEditable=${node.isEditable} isFocused=${node.isFocused} " +
            "isVisibleToUser=${node.isVisibleToUser} textLen=${node.text?.length ?: -1}"

    private fun setCursor(node: AccessibilityNodeInfo, cursor: Int): Boolean {
        val arguments = Bundle().apply {
            putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT, cursor)
            putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT, cursor)
        }
        return node.performAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, arguments)
    }

    private fun tryPasteAction(
        focusedNode: AccessibilityNodeInfo,
        text: String
    ): Boolean {
        return try {
            val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            clipboard.setPrimaryClip(ClipData.newPlainText("Transcription", text))
            val pasted = focusedNode.performAction(AccessibilityNodeInfo.ACTION_PASTE)
            if (pasted) {
                Log.d(TAG, "Direct insertion succeeded via ACTION_PASTE")
            } else {
                Log.d(TAG, "Focused cursor insertion failed: ACTION_PASTE returned false")
            }
            pasted
        } catch (e: Exception) {
            Log.e(TAG, "Focused cursor paste failed", e)
            false
        }
    }

    private fun copyToClipboard(text: String) {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("Transcription", text))
    }

    companion object {
        private const val TAG = "TextInsertionHelper"
    }
}

/**
 * AccessibilityService for text insertion and focus detection.
 * This service must be enabled by the user in system settings.
 */
class TextInsertionAccessibilityService : AccessibilityService() {

    /**
     * Snapshot of the last focused editable node. Updated on every TYPE_VIEW_FOCUSED
     * event so PillController can capture it synchronously at tap time, before the
     * network request clears input focus from the target app's window.
     */
    @Volatile
    var lastEditableNode: AccessibilityNodeInfo? = null
        private set

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        Log.d(TAG, "onServiceConnected")
        // Ensure interactive-window flag is set so we can read from other apps' windows.
        runCatching {
            val current = serviceInfo
            if (current != null) {
                current.flags = current.flags or AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
                serviceInfo = current
            }
        }
        com.echo.dictation.core.input.FocusAndKeyboardDetector.instance?.checkCurrentFocusState()
    }
    
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        // Forward focus events to FocusAndKeyboardDetector and maintain the editable snapshot.
        when (event.eventType) {
            AccessibilityEvent.TYPE_VIEW_FOCUSED -> {
                val src = event.source
                if (src != null && src.isEditable && !src.isPassword) {
                    lastEditableNode = src
                    Log.d(TAG, "Snapshot updated: ${src.packageName} / ${src.className}")
                }
                com.echo.dictation.core.input.FocusAndKeyboardDetector.instance
                    ?.onFocusChanged(event)
            }
            AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED,
            AccessibilityEvent.TYPE_VIEW_TEXT_SELECTION_CHANGED,
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED,
            AccessibilityEvent.TYPE_WINDOWS_CHANGED -> {
                com.echo.dictation.core.input.FocusAndKeyboardDetector.instance
                    ?.onFocusChanged(event)
            }
        }
    }
    
    override fun onInterrupt() {
        Log.w(TAG, "AccessibilityService interrupted")
    }

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        instance = null
        Log.d(TAG, "Service disconnected")
        return super.onUnbind(intent)
    }
    
    companion object {
        private const val TAG = "TextInsertionAccessibilityService"
        
        @Volatile
        var instance: TextInsertionAccessibilityService? = null
            internal set
    }
}
