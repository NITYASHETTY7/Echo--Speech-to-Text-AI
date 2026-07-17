package com.echo.dictation

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import androidx.core.content.ContextCompat
import androidx.navigation.compose.rememberNavController
import com.echo.dictation.presentation.navigation.NavigationGraph
import com.echo.dictation.presentation.theme.EchoTheme
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    // Register the permission launcher before onCreate (required by the API).
    private val requestMicPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            // Nothing extra to do: PillController re-checks hasRecordAudio() on every tap,
            // so it will start recording on the next tap if the user granted the permission.
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Request RECORD_AUDIO if not yet granted. This is required on Android 6+.
        // The floating mic's PillController silently refuses to record without it.
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED
        ) {
            requestMicPermission.launch(Manifest.permission.RECORD_AUDIO)
        }

        setContent {
            EchoTheme {
                Surface(Modifier.fillMaxSize()) {
                    NavigationGraph(rememberNavController())
                }
            }
        }
    }
}
