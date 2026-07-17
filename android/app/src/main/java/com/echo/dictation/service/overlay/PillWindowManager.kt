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
import android.view.ViewConfiguration
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
import kotlin.math.sqrt

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
    private var focusVisible = false

    private val componentCallbacks = object : ComponentCallbacks {
        override fun onConfigurationChanged(newConfig: Configuration) {
            val currentView = view ?: return
            val params = windowParams ?: return
            val context = overlayContext ?: return
            clampPosition(context, params)
            runCatching { manager?.updateViewLayout(currentView, params) }
            persistPosition(params)
        }

        override fun onLowMemory() = Unit
    }

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
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.RGBA_8888
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = preferences.floatingPillX.takeUnless { it == UNSET_POSITION } ?: 0
            y = preferences.floatingPillY.takeUnless { it == UNSET_POSITION } ?: appContext.dp(DEFAULT_Y_DP)
        }
        clampPosition(appContext, params, pillSize)
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
            // The overlay is present for touch handling and starts fully visible as confirmation
            // that the service was enabled. It transitions to idle after the startup grace period.
            alpha = 1f
            visibility = View.VISIBLE
            isClickable = true
            isEnabled = true
            isFocusable = false
            setOnClickListener {
                Log.d(TAG, "Floating pill clicked")
                onClick()
            }
        }

        val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
        var downRawX = 0f
        var downRawY = 0f
        var startX = 0
        var startY = 0
        var isDragging = false

        pill.setOnTouchListener { touchedView, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downRawX = event.rawX
                    downRawY = event.rawY
                    startX = params.x
                    startY = params.y
                    isDragging = false
                    true
                }

                MotionEvent.ACTION_MOVE -> {
                    val deltaX = event.rawX - downRawX
                    val deltaY = event.rawY - downRawY
                    val distance = sqrt(deltaX * deltaX + deltaY * deltaY)

                    if (!isDragging && distance > touchSlop) {
                        isDragging = true
                    }

                    if (isDragging) {
                        params.x = startX + deltaX.toInt()
                        params.y = startY + deltaY.toInt()
                        clampPosition(appContext, params, pillSize)
                        runCatching { windowManager.updateViewLayout(touchedView, params) }
                    }
                    true
                }

                MotionEvent.ACTION_UP -> {
                    if (isDragging) {
                        clampPosition(appContext, params, pillSize)
                        persistPosition(params)
                    } else {
                        // Route true taps through the existing click callback only.
                        touchedView.performClick()
                    }
                    isDragging = false
                    true
                }

                MotionEvent.ACTION_CANCEL -> {
                    if (isDragging) {
                        clampPosition(appContext, params, pillSize)
                        persistPosition(params)
                    }
                    isDragging = false
                    true
                }

                else -> true
            }
        }

        try {
            windowManager.addView(pill, params)
        } catch (error: Exception) {
            Log.e(
                TAG,
                "Overlay add failed: ${error.javaClass.simpleName}: ${error.message}",
                error
            )
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
        Log.d(TAG, "Overlay created")
        Log.d(TAG, "Overlay visible")
        applyPillState(controller.pillState.value)
        stateScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate).also { scope ->
            scope.launch {
                controller.pillState.collect { state ->
                    applyPillState(state)
                }
            }
        }
        Log.d(TAG, "Floating pill created")
        return true
    }

    private fun clampPosition(
        context: Context,
        params: WindowManager.LayoutParams,
        pillSize: Int = context.dp(PILL_SIZE_DP)
    ) {
        val metrics = context.resources.displayMetrics
        val visualSize = (pillSize * RECORDING_SCALE).toInt()
        val maxX = (metrics.widthPixels - visualSize).coerceAtLeast(0)
        val maxY = (metrics.heightPixels - visualSize).coerceAtLeast(0)
        params.x = params.x.coerceIn(0, maxX)
        params.y = params.y.coerceIn(0, maxY)
    }

    private fun persistPosition(params: WindowManager.LayoutParams) {
        preferences.floatingPillX = params.x
        preferences.floatingPillY = params.y
    }

    private fun applyPillState(pillState: PillState) {
        val currentView = view ?: return
        val isRecording     = pillState is PillState.Recording
        val isTranscribing  = pillState is PillState.Transcribing
        val wasRecording    = lastRecordingState == true

        if (lastRecordingState != isRecording) {
            Log.d(TAG, if (isRecording) "Recording started" else "Recording stopped")
            lastRecordingState = isRecording
        }

        val bgColor = when {
            isRecording    -> RECORDING_COLOR      // red
            isTranscribing -> TRANSCRIBING_COLOR   // amber/orange
            else           -> Color.BLACK
        }
        pillBackground?.setColor(bgColor)

        micIcon?.setImageResource(
            if (isRecording) R.drawable.ic_stop else R.drawable.ic_microphone
        )

        currentView.animate().cancel()
        currentView.visibility = View.VISIBLE

        val targetScale = when {
            isRecording    -> RECORDING_SCALE
            isTranscribing -> RECORDING_SCALE
            else           -> NORMAL_SCALE
        }
        val animation = currentView.animate()
            .scaleX(targetScale)
            .scaleY(targetScale)
            .setDuration(SCALE_ANIMATION_DURATION_MS)

        if (isRecording || isTranscribing || wasRecording) {
            animation.alpha(if (isRecording || isTranscribing || focusVisible) 1f else IDLE_ALPHA)
        }
        animation.start()
    }

    fun setVisibility(visible: Boolean) {
        focusVisible = visible
        val currentView = view ?: return
        currentView.animate().cancel()
        currentView.visibility = View.VISIBLE

        // Keep the pill fully visible while recording OR transcribing.
        if (lastRecordingState == true) return
        if (controller.pillState.value is PillState.Transcribing) return

        if (visible) {
            currentView.animate()
                .alpha(1f)
                .setDuration(VISIBILITY_ANIMATION_DURATION_MS)
                .withEndAction {
                    currentView.alpha = 1f
                    currentView.visibility = View.VISIBLE
                    Log.d(TAG, "Overlay visible")
                }
                .start()
        } else {
            currentView.animate()
                .alpha(IDLE_ALPHA)
                .setDuration(VISIBILITY_ANIMATION_DURATION_MS)
                .withEndAction {
                    currentView.alpha = IDLE_ALPHA
                    currentView.visibility = View.VISIBLE
                    Log.d(TAG, "Overlay faded")
                }
                .start()
        }
    }

    fun remove() {
        stateScope?.cancel()
        stateScope = null
        callbacksContext?.unregisterComponentCallbacks(componentCallbacks)
        callbacksContext = null
        view?.let { currentView ->
            try {
                manager?.removeView(currentView)
                Log.d(TAG, "Overlay removed from WindowManager")
            } catch (error: Exception) {
                Log.e(
                    TAG,
                    "Overlay remove failed: ${error.javaClass.simpleName}: ${error.message}",
                    error
                )
            }
        }
        view = null
        manager = null
        windowParams = null
        overlayContext = null
        micIcon = null
        pillBackground = null
        lastRecordingState = null
        focusVisible = false
    }

    private fun Context.dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    companion object {
        private const val TAG = "PillWindowManager"
        private const val PILL_SIZE_DP = 56
        private const val DEFAULT_Y_DP = 160
        private const val UNSET_POSITION = Int.MIN_VALUE
        private const val RECORDING_COLOR = 0xffc62828.toInt()
        private const val TRANSCRIBING_COLOR = 0xffe65100.toInt()  // deep amber — "processing"
        private const val RECORDING_SCALE = 1.1f
        private const val NORMAL_SCALE = 1f
        private const val IDLE_ALPHA = 0.3f
        private const val SCALE_ANIMATION_DURATION_MS = 120L
        private const val VISIBILITY_ANIMATION_DURATION_MS = 200L
    }
}
