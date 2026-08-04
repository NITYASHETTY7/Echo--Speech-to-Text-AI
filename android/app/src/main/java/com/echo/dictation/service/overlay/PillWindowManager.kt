package com.echo.dictation.service.overlay

import android.content.ComponentCallbacks
import android.content.Context
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import com.echo.dictation.R
import com.echo.dictation.data.local.AppPreferences
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.abs

/**
 * Manages the floating microphone overlay window.
 *
 * Interaction model (tap-to-record):
 *   • First tap  → start recording (calls controller.toggleState())
 *   • Second tap → stop recording  (calls controller.toggleState())
 *   • Drag > [TAP_SLOP_DP] → reposition only, never toggles recording
 *
 * Snap-to-edge: on drag release the pill snaps to the nearer horizontal edge
 * (left or right) with a [EDGE_MARGIN_DP] margin, preserving the Y position.
 *
 * Visibility: when [setVisibility] is called with `false` the view is set to
 * [View.GONE] (no layout space, no touch events). `true` fades it in smoothly.
 */
@Singleton
class PillWindowManager @Inject constructor(
    private val controller: PillController,
    private val preferences: AppPreferences
) {
    private var manager: WindowManager? = null
    private var view: FrameLayout? = null
    private var micIcon: ImageView? = null
    private var pillBackground: GradientDrawable? = null
    private var stateScope: CoroutineScope? = null
    private var windowParams: WindowManager.LayoutParams? = null
    private var overlayContext: Context? = null
    private var callbacksContext: Context? = null
    private var lastRecordingState: Boolean? = null

    // True when the overlay is supposed to be shown (focus + injection available).
    private var shouldBeVisible = false

    private val componentCallbacks = object : ComponentCallbacks {
        override fun onConfigurationChanged(newConfig: Configuration) {
            val currentView = view ?: return
            val params = windowParams ?: return
            val context = overlayContext ?: return
            snapToEdge(context, params)
            runCatching { manager?.updateViewLayout(currentView, params) }
            persistPosition(params)
        }

        override fun onLowMemory() = Unit
    }

    // ─── Public API ──────────────────────────────────────────────────────────

    fun show(context: Context, onClick: () -> Unit): Boolean {
        if (view != null) return true

        val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val appContext = context.applicationContext
        manager = windowManager
        overlayContext = appContext
        callbacksContext = appContext
        appContext.registerComponentCallbacks(componentCallbacks)

        val type = if (Build.VERSION.SDK_INT >= 26) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE
        }

        val pillSize = appContext.dp(PILL_SIZE_DP)
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.RGBA_8888
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = preferences.floatingPillX.takeUnless { it == UNSET_POSITION }
                ?: edgeSnappedX(appContext, isRight = true, pillSize = pillSize)
            y = preferences.floatingPillY.takeUnless { it == UNSET_POSITION }
                ?: appContext.dp(DEFAULT_Y_DP)
        }
        // Ensure saved position is still on-screen and snapped after a resolution change.
        snapToEdge(appContext, params, pillSize)
        windowParams = params

        val icon = ImageView(context).apply {
            setImageResource(R.drawable.ic_microphone)
            setColorFilter(Color.WHITE)
            layoutParams = FrameLayout.LayoutParams(
                context.dp(24),
                context.dp(24),
                Gravity.CENTER
            )
        }
        micIcon = icon

        val bgDrawable = GradientDrawable().apply {
            setColor(Color.BLACK)
            cornerRadius = context.dp(28).toFloat()
        }
        pillBackground = bgDrawable

        val pill = FrameLayout(context).apply {
            setPadding(context.dp(16), context.dp(16), context.dp(16), context.dp(16))
            background = bgDrawable
            layoutParams = FrameLayout.LayoutParams(pillSize, pillSize)
            addView(icon)
            contentDescription = "Floating transcription pill"
            alpha = 1f
            // Start GONE — setVisibility(true) is called by PillOverlayService once a
            // text-field is focused and injection is confirmed available.
            visibility = View.GONE
            isClickable = true
            isEnabled = true
            isFocusable = false
            setOnClickListener {
                Log.d(TAG, "Pill clicked → toggleState()")
                onClick()
            }
        }

        pill.setOnTouchListener(buildTouchListener(pill, appContext, windowManager, params, pillSize, onClick))

        try {
            windowManager.addView(pill, params)
        } catch (error: Exception) {
            Log.e(TAG, "Overlay add failed: ${error.javaClass.simpleName}: ${error.message}", error)
            callbacksContext?.unregisterComponentCallbacks(componentCallbacks)
            callbacksContext = null
            manager = null
            windowParams = null
            overlayContext = null
            micIcon = null
            pillBackground = null
            return false
        }

        view = pill
        applyPillState(controller.pillState.value)

        stateScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate).also { scope ->
            scope.launch {
                controller.pillState.collect { state ->
                    applyPillState(state)
                }
            }
        }

        Log.d(TAG, "Floating pill created (hidden until focus+injection ready)")
        return true
    }

    /**
     * Show or completely hide the floating mic.
     *
     * Called by [PillOverlayService] whenever [FocusAndKeyboardDetector.shouldShowFloatingMic]
     * changes. A `false` value collapses the view to [View.GONE] so it occupies no screen
     * space and receives no touch events. A `true` value fades it in.
     *
     * If the user is currently recording or transcribing the pill stays visible regardless,
     * so an in-progress session is never hidden mid-recording.
     */
    fun setVisibility(visible: Boolean) {
        shouldBeVisible = visible
        val currentView = view ?: return

        // Never hide while an active session is in progress.
        val activeSession = lastRecordingState == true ||
                controller.pillState.value is PillState.Transcribing
        if (activeSession) return

        currentView.animate().cancel()

        if (visible) {
            currentView.alpha = 0f
            currentView.visibility = View.VISIBLE
            currentView.animate()
                .alpha(1f)
                .setDuration(VISIBILITY_ANIMATION_DURATION_MS)
                .withEndAction { currentView.alpha = 1f }
                .start()
            Log.d(TAG, "Mic shown (focus+injection available)")
        } else {
            if (currentView.visibility != View.GONE) {
                currentView.animate()
                    .alpha(0f)
                    .setDuration(VISIBILITY_ANIMATION_DURATION_MS)
                    .withEndAction {
                        currentView.visibility = View.GONE
                        currentView.alpha = 1f  // reset so the fade-in next time starts clean
                    }
                    .start()
                Log.d(TAG, "Mic hidden (focus/injection unavailable)")
            }
        }
    }

    fun remove() {
        stateScope?.cancel()
        stateScope = null
        callbacksContext?.unregisterComponentCallbacks(componentCallbacks)
        callbacksContext = null
        view?.let { currentView ->
            runCatching {
                manager?.removeView(currentView)
                Log.d(TAG, "Overlay removed from WindowManager")
            }.onFailure { e ->
                Log.e(TAG, "Overlay remove failed: ${e.javaClass.simpleName}: ${e.message}", e)
            }
        }
        view = null
        manager = null
        windowParams = null
        overlayContext = null
        micIcon = null
        pillBackground = null
        lastRecordingState = null
        shouldBeVisible = false
    }

    // ─── Touch handler (drag + tap-to-record) ────────────────────────────────

    /**
     * State machine:
     *
     *   ACTION_DOWN  → record raw start position; mark isDragging = false
     *   ACTION_MOVE  → if displacement > [TAP_SLOP_DP] set isDragging = true and
     *                  reposition the window in real time (60 FPS)
     *   ACTION_UP    → if isDragging: snap to nearest edge, persist position
     *                  if tap:        delegate to performClick() → toggleState()
     *   ACTION_CANCEL→ if isDragging: snap and persist; recording untouched
     */
    private fun buildTouchListener(
        pill: FrameLayout,
        appContext: Context,
        windowManager: WindowManager,
        params: WindowManager.LayoutParams,
        pillSize: Int,
        onClick: () -> Unit
    ) = View.OnTouchListener { touchedView, event ->
        when (event.actionMasked) {

            MotionEvent.ACTION_DOWN -> {
                touchState.downRawX = event.rawX
                touchState.downRawY = event.rawY
                touchState.startX   = params.x
                touchState.startY   = params.y
                touchState.isDragging = false
                true
            }

            MotionEvent.ACTION_MOVE -> {
                val dx = event.rawX - touchState.downRawX
                val dy = event.rawY - touchState.downRawY

                if (!touchState.isDragging) {
                    val distanceDp = appContext.pxToDp(
                        kotlin.math.sqrt(dx * dx + dy * dy)
                    )
                    if (distanceDp > TAP_SLOP_DP) {
                        touchState.isDragging = true
                        Log.d(TAG, "Drag started (${distanceDp.toInt()}dp)")
                    }
                }

                if (touchState.isDragging) {
                    params.x = (touchState.startX + dx.toInt()).coerceIn(0, maxX(appContext, pillSize))
                    params.y = (touchState.startY + dy.toInt()).coerceIn(0, maxY(appContext, pillSize))
                    runCatching { windowManager.updateViewLayout(touchedView, params) }
                }
                true
            }

            MotionEvent.ACTION_UP -> {
                if (touchState.isDragging) {
                    // Snap to the nearest horizontal edge.
                    snapToEdge(appContext, params, pillSize)
                    runCatching { windowManager.updateViewLayout(touchedView, params) }
                    persistPosition(params)
                    Log.d(TAG, "Drag released → snapped to x=${params.x}")
                } else {
                    // Pure tap — route through the click listener → toggleState().
                    Log.d(TAG, "Tap detected → performClick()")
                    touchedView.performClick()
                }
                touchState.isDragging = false
                true
            }

            MotionEvent.ACTION_CANCEL -> {
                if (touchState.isDragging) {
                    // System interrupted drag (e.g. notification shade). Snap and save.
                    snapToEdge(appContext, params, pillSize)
                    runCatching { windowManager.updateViewLayout(touchedView, params) }
                    persistPosition(params)
                    Log.d(TAG, "Drag cancelled → snapped to x=${params.x}")
                }
                touchState.isDragging = false
                true
            }

            else -> false
        }
    }

    // Single object to avoid repeated local-variable allocation inside the touch listener.
    private val touchState = object {
        var downRawX  = 0f
        var downRawY  = 0f
        var startX    = 0
        var startY    = 0
        var isDragging = false
    }

    // ─── Position helpers ────────────────────────────────────────────────────

    /**
     * Snap params.x to the nearer of the left or right edge, maintaining [EDGE_MARGIN_DP].
     * params.y is unchanged (vertical position is fully free-form).
     */
    private fun snapToEdge(
        context: Context,
        params: WindowManager.LayoutParams,
        pillSize: Int = context.dp(PILL_SIZE_DP)
    ) {
        val metrics    = context.resources.displayMetrics
        val screenW    = metrics.widthPixels
        val margin     = context.dp(EDGE_MARGIN_DP)
        val rightEdgeX = screenW - pillSize - margin

        // Clamp Y so the pill stays fully on screen.
        val maxYPx = maxY(context, pillSize)
        params.y = params.y.coerceIn(0, maxYPx)

        // Snap X to whichever edge is closer.
        val centerX = params.x + pillSize / 2
        params.x = if (centerX < screenW / 2) margin else rightEdgeX
    }

    private fun edgeSnappedX(context: Context, isRight: Boolean, pillSize: Int): Int {
        val metrics = context.resources.displayMetrics
        val margin  = context.dp(EDGE_MARGIN_DP)
        return if (isRight) metrics.widthPixels - pillSize - margin else margin
    }

    private fun maxX(context: Context, pillSize: Int = context.dp(PILL_SIZE_DP)): Int {
        val scale = if (lastRecordingState == true) RECORDING_SCALE else NORMAL_SCALE
        return (context.resources.displayMetrics.widthPixels - pillSize * scale).toInt()
            .coerceAtLeast(0)
    }

    private fun maxY(context: Context, pillSize: Int = context.dp(PILL_SIZE_DP)): Int {
        val scale = if (lastRecordingState == true) RECORDING_SCALE else NORMAL_SCALE
        return (context.resources.displayMetrics.heightPixels - pillSize * scale).toInt()
            .coerceAtLeast(0)
    }

    private fun persistPosition(params: WindowManager.LayoutParams) {
        preferences.floatingPillX = params.x
        preferences.floatingPillY = params.y
    }

    // ─── Visual state ────────────────────────────────────────────────────────

    private fun applyPillState(pillState: PillState) {
        val currentView = view ?: return
        val isRecording    = pillState is PillState.Recording
        val isTranscribing = pillState is PillState.Transcribing
        val wasRecording   = lastRecordingState == true

        if (lastRecordingState != isRecording) {
            Log.d(TAG, if (isRecording) "Recording started" else "Recording stopped")
            lastRecordingState = isRecording
        }

        // While recording or transcribing, force visibility regardless of focus state.
        if (isRecording || isTranscribing) {
            currentView.visibility = View.VISIBLE
            currentView.alpha = 1f
        } else if (wasRecording) {
            // Session just ended — re-apply the current shouldBeVisible state.
            // Use setVisibility() so the correct GONE/VISIBLE + animation is applied.
            setVisibility(shouldBeVisible)
        }

        val bgColor = when {
            isRecording    -> RECORDING_COLOR
            isTranscribing -> TRANSCRIBING_COLOR
            else           -> Color.BLACK
        }
        pillBackground?.setColor(bgColor)

        micIcon?.setImageResource(
            if (isRecording) R.drawable.ic_stop else R.drawable.ic_microphone
        )

        currentView.animate().cancel()
        val targetScale = if (isRecording || isTranscribing) RECORDING_SCALE else NORMAL_SCALE
        currentView.animate()
            .scaleX(targetScale)
            .scaleY(targetScale)
            .setDuration(SCALE_ANIMATION_DURATION_MS)
            .start()
    }

    // ─── Utilities ────────────────────────────────────────────────────────────

    private fun Context.dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    private fun Context.pxToDp(px: Float): Float =
        px / resources.displayMetrics.density

    // ─── Constants ────────────────────────────────────────────────────────────

    companion object {
        private const val TAG = "PillWindowManager"

        private const val PILL_SIZE_DP  = 56
        private const val DEFAULT_Y_DP  = 160
        private const val EDGE_MARGIN_DP = 16

        /** Any finger movement beyond this dp threshold during a touch is classified as a drag. */
        private const val TAP_SLOP_DP = 10f

        private const val UNSET_POSITION = Int.MIN_VALUE

        private const val RECORDING_COLOR   = 0xffc62828.toInt()   // deep red
        private const val TRANSCRIBING_COLOR = 0xffe65100.toInt()  // deep amber

        private const val RECORDING_SCALE           = 1.1f
        private const val NORMAL_SCALE              = 1f
        private const val SCALE_ANIMATION_DURATION_MS   = 120L
        private const val VISIBILITY_ANIMATION_DURATION_MS = 200L
    }
}
