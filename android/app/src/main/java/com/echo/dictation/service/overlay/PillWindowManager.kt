package com.echo.dictation.service.overlay

import android.content.ComponentCallbacks
import android.content.Context
import android.content.res.Configuration
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
    private var pillIcon: ImageView? = null
    private var processingRing: ImageView? = null
    private var pillBackground: GradientDrawable? = null
    private var stateScope: CoroutineScope? = null
    private var windowParams: WindowManager.LayoutParams? = null
    private var overlayContext: Context? = null
    private var callbacksContext: Context? = null
    private var lastRecordingState: Boolean? = null

    /** Infinite "breathing" pulse used while recording. */
    private var pulseAnimator: android.animation.ObjectAnimator? = null
    /** Infinite rotation of [processingRing] used while transcribing. */
    private var spinAnimator: android.animation.ObjectAnimator? = null

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

        // Content area available to the icon = pill size minus the FrameLayout's own
        // padding on both sides. Sizing the icon relative to this (not the raw pillSize)
        // is what makes it actually occupy ~85–90% of the *visible* button area.
        val pillPadding = context.dp(PILL_PADDING_DP)
        val contentArea = pillSize - (pillPadding * 2)

        val icon = ImageView(context).apply {
            setImageResource(R.drawable.ic_echo_mic_wave)
            // No tint / color filter — the glyph is already pure white; it reads on the
            // colour-changing gradient background (lavender / red / amber per state).
            scaleType = ImageView.ScaleType.FIT_CENTER
            adjustViewBounds = true
            layoutParams = FrameLayout.LayoutParams(
                (contentArea * ICON_SIZE_RATIO).toInt(),
                (contentArea * ICON_SIZE_RATIO).toInt(),
                Gravity.CENTER
            )
        }
        pillIcon = icon

        // Processing spinner — a rotating arc "halo" shown only while transcribing.
        // Sized to the full content area so it rings just outside the glyph. Starts GONE;
        // applyPillState() shows + rotates it during PillState.Transcribing only.
        val ring = ImageView(context).apply {
            setImageResource(R.drawable.ic_processing_ring)
            scaleType = ImageView.ScaleType.FIT_CENTER
            layoutParams = FrameLayout.LayoutParams(contentArea, contentArea, Gravity.CENTER)
            visibility = View.GONE
        }
        processingRing = ring

        // Idle state: soft lavender → violet gradient (the new Echo identity).
        // Recording/transcribing temporarily override this with a solid color via
        // setColor(), then applyPillState() restores the gradient via setColors().
        val bgDrawable = GradientDrawable(
            GradientDrawable.Orientation.TL_BR,
            intArrayOf(IDLE_GRADIENT_START, IDLE_GRADIENT_CENTER, IDLE_GRADIENT_END)
        ).apply {
            gradientType = GradientDrawable.LINEAR_GRADIENT
            cornerRadius = context.dp(20).toFloat()
        }
        pillBackground = bgDrawable

        val pill = FrameLayout(context).apply {
            setPadding(pillPadding, pillPadding, pillPadding, pillPadding)
            background = bgDrawable
            layoutParams = FrameLayout.LayoutParams(pillSize, pillSize)
            addView(ring)
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
            pillIcon = null
            processingRing = null
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
        longPressHandler.removeCallbacks(longPressRunnable)
        pulseAnimator?.cancel()
        pulseAnimator = null
        spinAnimator?.cancel()
        spinAnimator = null
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
        pillIcon = null
        processingRing = null
        pillBackground = null
        lastRecordingState = null
        shouldBeVisible = false
    }

    // ─── Touch handler (drag + tap-to-record) ────────────────────────────────

    /**
     * State machine:
     *
     *   ACTION_DOWN  → record raw start position; mark isDragging = false;
     *                  schedule a long-press callback after [LONG_PRESS_TIMEOUT_MS]
     *   ACTION_MOVE  → if displacement > [TAP_SLOP_DP] set isDragging = true, cancel the
     *                  long-press callback, and reposition the window in real time (60 FPS)
     *   ACTION_UP    → cancel any pending long-press callback;
     *                  if isDragging: snap to nearest edge, persist position
     *                  if tap:        delegate to performClick() → toggleState()
     *   ACTION_CANCEL→ cancel any pending long-press callback;
     *                  if isDragging: snap and persist; recording untouched
     *
     * Long-press (held in place past [LONG_PRESS_TIMEOUT_MS] without dragging) opens
     * the Snooze bottom sheet via [SnoozeActivity] instead of toggling recording.
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
                touchState.longPressTriggered = false
                longPressHandler.removeCallbacks(longPressRunnable)
                longPressRunnable = Runnable {
                    if (!touchState.isDragging) {
                        touchState.longPressTriggered = true
                        Log.d(TAG, "Long-press detected → opening Snooze sheet")
                        launchSnoozeActivity(appContext)
                    }
                }
                longPressHandler.postDelayed(longPressRunnable, LONG_PRESS_TIMEOUT_MS)
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
                        longPressHandler.removeCallbacks(longPressRunnable)
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
                longPressHandler.removeCallbacks(longPressRunnable)
                if (touchState.longPressTriggered) {
                    // Long-press already handled the gesture — do not also toggle recording.
                    touchState.isDragging = false
                    touchState.longPressTriggered = false
                    return@OnTouchListener true
                }
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
                longPressHandler.removeCallbacks(longPressRunnable)
                touchState.longPressTriggered = false
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

    /**
     * Launches [com.echo.dictation.presentation.ui.SnoozeActivity] as a translucent,
     * task-affinity-less trampoline so the Snooze bottom sheet appears over whatever
     * app is currently in the foreground. FLAG_ACTIVITY_NEW_TASK is required because
     * the overlay view's context is not itself an Activity context.
     */
    private fun launchSnoozeActivity(context: Context) {
        val intent = android.content.Intent(context, com.echo.dictation.presentation.ui.SnoozeActivity::class.java)
            .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { context.startActivity(intent) }
            .onFailure { e -> Log.e(TAG, "Failed to launch SnoozeActivity: ${e.message}", e) }
    }

    // Single object to avoid repeated local-variable allocation inside the touch listener.
    private val touchState = object {
        var downRawX  = 0f
        var downRawY  = 0f
        var startX    = 0
        var startY    = 0
        var isDragging = false
        var longPressTriggered = false
    }

    private val longPressHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private var longPressRunnable: Runnable = Runnable {}

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
            else           -> null // idle → restore the lavender gradient below
        }
        if (bgColor != null) {
            pillBackground?.setColor(bgColor)
        } else {
            pillBackground?.setColors(intArrayOf(IDLE_GRADIENT_START, IDLE_GRADIENT_CENTER, IDLE_GRADIENT_END))
        }

        // Icon is a static image (Echo glyph). Recording vs. Transcribing are made
        // unmistakable by giving each state its own motion (not just a color swap):
        //   • Recording    → deep-red background + a continuous "breathing" pulse.
        //   • Transcribing → amber background + a rotating spinner ring (halo) around the glyph.
        //   • Idle         → lavender gradient, no motion, resting scale.
        stopStateAnimations(currentView)
        when {
            isRecording -> {
                processingRing?.visibility = View.GONE
                startRecordingPulse(currentView)
            }
            isTranscribing -> {
                currentView.scaleX = RECORDING_SCALE
                currentView.scaleY = RECORDING_SCALE
                processingRing?.let { ring ->
                    ring.visibility = View.VISIBLE
                    startProcessingSpin(ring)
                }
            }
            else -> {
                processingRing?.visibility = View.GONE
                currentView.animate()
                    .scaleX(NORMAL_SCALE)
                    .scaleY(NORMAL_SCALE)
                    .setDuration(SCALE_ANIMATION_DURATION_MS)
                    .start()
            }
        }
    }

    /** Cancels any running recording-pulse / transcribing-spin animations and resets transforms. */
    private fun stopStateAnimations(currentView: View) {
        currentView.animate().cancel()
        pulseAnimator?.cancel()
        pulseAnimator = null
        spinAnimator?.cancel()
        spinAnimator = null
        processingRing?.rotation = 0f
    }

    /** Continuous gentle scale pulse — signals "live, capturing audio". */
    private fun startRecordingPulse(currentView: View) {
        val scaleX = android.animation.PropertyValuesHolder.ofFloat(
            View.SCALE_X, RECORDING_PULSE_MIN, RECORDING_PULSE_MAX
        )
        val scaleY = android.animation.PropertyValuesHolder.ofFloat(
            View.SCALE_Y, RECORDING_PULSE_MIN, RECORDING_PULSE_MAX
        )
        pulseAnimator = android.animation.ObjectAnimator.ofPropertyValuesHolder(currentView, scaleX, scaleY).apply {
            duration = RECORDING_PULSE_DURATION_MS
            repeatCount = android.animation.ObjectAnimator.INFINITE
            repeatMode = android.animation.ObjectAnimator.REVERSE
            interpolator = android.view.animation.AccelerateDecelerateInterpolator()
            start()
        }
    }

    /** Continuous rotation of the arc ring — signals "processing / transcribing". */
    private fun startProcessingSpin(ring: ImageView) {
        spinAnimator = android.animation.ObjectAnimator.ofFloat(ring, View.ROTATION, 0f, 360f).apply {
            duration = PROCESSING_SPIN_DURATION_MS
            repeatCount = android.animation.ObjectAnimator.INFINITE
            repeatMode = android.animation.ObjectAnimator.RESTART
            interpolator = android.view.animation.LinearInterpolator()
            start()
        }
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
        private const val PILL_PADDING_DP = 16

        /** Icon occupies this fraction of the pill's content area (85–90% target). */
        private const val ICON_SIZE_RATIO = 0.87f

        /** Echo's idle-state identity gradient — warm nude/dusty-rose, per user spec. */
        private const val IDLE_GRADIENT_START  = 0xFFE1C4BD.toInt()
        private const val IDLE_GRADIENT_CENTER = 0xFFD5B4AC.toInt()
        private const val IDLE_GRADIENT_END    = 0xFFC9A49C.toInt()

        /** Any finger movement beyond this dp threshold during a touch is classified as a drag. */
        private const val TAP_SLOP_DP = 10f

        /** Holding the pill in place (no drag) for this long opens the Snooze bottom sheet. */
        private const val LONG_PRESS_TIMEOUT_MS = 500L

        private const val UNSET_POSITION = Int.MIN_VALUE

        private const val RECORDING_COLOR   = 0xffc62828.toInt()   // deep red
        private const val TRANSCRIBING_COLOR = 0xffe65100.toInt()  // deep amber

        private const val RECORDING_SCALE           = 1.1f
        private const val NORMAL_SCALE              = 1f
        private const val SCALE_ANIMATION_DURATION_MS   = 120L
        private const val VISIBILITY_ANIMATION_DURATION_MS = 200L

        /** Recording "breathing" pulse bounds + speed. */
        private const val RECORDING_PULSE_MIN = 1.02f
        private const val RECORDING_PULSE_MAX = 1.18f
        private const val RECORDING_PULSE_DURATION_MS = 650L

        /** Transcribing spinner: one full rotation per this many ms. */
        private const val PROCESSING_SPIN_DURATION_MS = 900L
    }
}
