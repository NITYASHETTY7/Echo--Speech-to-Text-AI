package com.echo.dictation.service.overlay

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.echo.dictation.MainActivity
import com.echo.dictation.R
import com.echo.dictation.core.input.FocusAndKeyboardDetector
import com.echo.dictation.core.permission.PermissionManager
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay
import javax.inject.Inject

@AndroidEntryPoint
class PillOverlayService : Service() {
    @Inject lateinit var permissions: PermissionManager
    @Inject lateinit var windows: PillWindowManager
    @Inject lateinit var controller: PillController
    @Inject lateinit var focusDetector: FocusAndKeyboardDetector

    private var visibilityScope: CoroutineScope? = null

    override fun onCreate() {
        super.onCreate()
        runningState.value = true
        controller.serviceContext = applicationContext   // needed for Toasts from service
        Log.d(TAG, "Overlay Service started")
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, notification())
        if (permissions.hasOverlay()) {
            // The AccessibilityService forwards focus events to this shared detector.
            // The detector controls visibility only; recording remains in PillController.
            FocusAndKeyboardDetector.instance = focusDetector
            // Prime the state for a field that was already focused before the overlay started.
            focusDetector.checkCurrentFocusState()
            val overlayAdded = windows.show(this, ::onPillClicked)
            if (!overlayAdded) {
                stopSelf()
            } else if (visibilityScope == null) {
                visibilityScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate).also { scope ->
                    scope.launch {
                        delay(INITIAL_VISIBLE_DURATION_MS)
                        windows.setVisibility(focusDetector.shouldShowFloatingMic.value)
                        focusDetector.shouldShowFloatingMic.collect { shouldShow ->
                            windows.setVisibility(shouldShow)
                        }
                    }
                }
            }
        } else {
            requestOverlayPermission()
            stopSelf()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        visibilityScope?.cancel()
        visibilityScope = null
        if (FocusAndKeyboardDetector.instance === focusDetector) {
            FocusAndKeyboardDetector.instance = null
        }
        controller.cleanup()
        windows.remove()
        runningState.value = false
        Log.d(TAG, "Overlay Service stopped")
        Log.d(TAG, "Overlay destroyed")
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun onPillClicked() {
        controller.toggleState()
    }

    private fun requestOverlayPermission() {
        startActivity(permissions.overlayIntent().addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= 26) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(CHANNEL, "Echo overlay", NotificationManager.IMPORTANCE_LOW)
            )
        }
    }

    private fun notification(): Notification {
        val open = PendingIntent.getActivity(
            this,
            1,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_microphone)
            .setContentTitle("Echo is ready")
            .setContentIntent(open)
            .setOngoing(true)
            .build()
    }

    companion object {
        private const val TAG = "PillOverlayService"
        private const val CHANNEL = "overlay"
        private const val NOTIFICATION_ID = 21
        private const val INITIAL_VISIBLE_DURATION_MS = 2_000L

        private val runningState = MutableStateFlow(false)
        val isRunning: StateFlow<Boolean> = runningState.asStateFlow()

        fun start(context: Context) {
            val intent = Intent(context, PillOverlayService::class.java)
            if (Build.VERSION.SDK_INT >= 26) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, PillOverlayService::class.java))
        }
    }
}

