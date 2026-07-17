package com.echo.dictation.service

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.echo.dictation.data.local.AppPreferences
import com.echo.dictation.service.overlay.PillOverlayService
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject

@AndroidEntryPoint
class BootReceiver : BroadcastReceiver() {
    @Inject lateinit var preferences: AppPreferences
    override fun onReceive(context: Context, intent: Intent) { if (intent.action == Intent.ACTION_BOOT_COMPLETED && preferences.autoStart) PillOverlayService.start(context) }
}
