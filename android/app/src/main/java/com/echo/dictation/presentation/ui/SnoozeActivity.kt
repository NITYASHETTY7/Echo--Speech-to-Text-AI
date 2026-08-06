package com.echo.dictation.presentation.ui

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.getValue
import androidx.compose.runtime.collectAsState
import com.echo.dictation.core.input.SnoozeManager
import com.echo.dictation.data.local.AppPreferences
import com.echo.dictation.presentation.theme.EchoTheme
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject

/**
 * Transparent trampoline Activity that hosts only [SnoozeOptionsBottomSheet].
 *
 * Launched from the Floating Pill's long-press action ([com.echo.dictation.service.overlay.PillWindowManager]).
 * A dedicated Activity is used (rather than trying to host Compose directly inside the
 * overlay window) because [android.view.WindowManager] overlay views cannot easily host
 * a Material3 ModalBottomSheet with its own window/backdrop. The activity is themed as
 * translucent so it visually behaves like a sheet popping over whatever app is currently
 * in the foreground, and finishes itself immediately after a selection or dismissal —
 * it never becomes part of the normal back stack / navigation graph.
 */
@AndroidEntryPoint
class SnoozeActivity : ComponentActivity() {

    @Inject lateinit var snoozeManager: SnoozeManager
    @Inject lateinit var prefs: AppPreferences

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        setContent {
            val themePref by prefs.themeFlow.collectAsState()
            val systemDark = isSystemInDarkTheme()
            val darkTheme = when (themePref) {
                "dark"  -> true
                "light" -> false
                else    -> systemDark
            }

            EchoTheme(darkTheme = darkTheme) {
                SnoozeOptionsBottomSheet(
                    onDurationSelected = { duration ->
                        val durationMs = duration.toDurationMsOrNull()
                        if (durationMs != null) {
                            snoozeManager.snoozeFor(durationMs)
                        } else {
                            snoozeManager.snoozeIndefinitely()
                        }
                        finish()
                    },
                    onDismiss = { finish() },
                )
            }
        }
    }
}
