package com.echo.dictation

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import androidx.navigation.compose.rememberNavController
import com.echo.dictation.data.local.AppPreferences
import com.echo.dictation.presentation.navigation.NavigationGraph
import com.echo.dictation.presentation.theme.EchoTheme
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject

@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    /**
     * Injected as a singleton so the same [AppPreferences] instance that
     * [SettingsViewModel] writes to is observed here.  When the user changes
     * the theme in Settings, [AppPreferences.themeFlow] emits the new value
     * and [EchoTheme] recomposes immediately — no app restart required.
     */
    @Inject
    lateinit var prefs: AppPreferences

    private val requestMicPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { _ -> }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Edge-to-edge: Compose owns the full window surface.
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor     = Color.Transparent.toArgb()
        window.navigationBarColor = Color.Transparent.toArgb()

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED
        ) {
            requestMicPermission.launch(Manifest.permission.RECORD_AUDIO)
        }

        setContent {
            // Observe the persisted theme preference reactively.
            // Any change in Settings immediately triggers recomposition here.
            val themePref by prefs.themeFlow.collectAsState()
            val systemDark = isSystemInDarkTheme()

            val darkTheme = when (themePref) {
                "dark"  -> true
                "light" -> false
                else    -> systemDark   // "system" — follow device setting
            }

            // Keep system bar icon colours in sync with the active theme.
            SideEffect {
                val controller = WindowCompat.getInsetsController(window, window.decorView)
                controller.isAppearanceLightStatusBars     = !darkTheme
                controller.isAppearanceLightNavigationBars = !darkTheme
            }

            EchoTheme(darkTheme = darkTheme) {
                Surface(Modifier.fillMaxSize()) {
                    NavigationGraph(rememberNavController())
                }
            }
        }
    }
}
