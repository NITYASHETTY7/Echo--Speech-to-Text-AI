package com.echo.dictation.presentation.ui.auth

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.CloudSync
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.echo.dictation.presentation.theme.CardColor
import com.echo.dictation.presentation.theme.OnSurfaceVariant
import com.echo.dictation.presentation.theme.Primary
import com.echo.dictation.presentation.theme.PrimaryColor
import com.echo.dictation.presentation.theme.PrimaryVariant

@Composable
fun WelcomeOnboardingScreen(
    uiState: AuthUiState = AuthUiState.Idle,
    onGoogleSignInClick: () -> Unit,
    onSkipClick: () -> Unit,
) {
    val isLoading    = uiState is AuthUiState.Loading
    val errorMessage = (uiState as? AuthUiState.Error)?.message

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.surface)
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.SpaceBetween,
    ) {
        // Top spacer — keeps content balanced now that the Skip row is removed
        Spacer(Modifier.height(8.dp))

        // Header illustration
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Box(
                modifier = Modifier
                    .size(90.dp)
                    .clip(CircleShape)
                    .background(Brush.linearGradient(listOf(PrimaryColor, PrimaryVariant))),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector        = Icons.Default.Mic,
                    contentDescription = "Echo Logo",
                    tint               = Color.White,
                    modifier           = Modifier.size(44.dp),
                )
            }
            Text(
                text       = "Welcome to Echo",
                style      = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
                color      = MaterialTheme.colorScheme.onSurface,
                textAlign  = TextAlign.Center,
            )
            Text(
                text      = "AI-powered dictation, instant rewrites & cross-device cloud sync",
                style     = MaterialTheme.typography.bodyMedium,
                color     = OnSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }

        // Feature highlights
        Column(
            modifier            = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            FeatureHighlightRow(
                icon        = Icons.Default.Mic,
                title       = "Speech to Text",
                description = "Fast and accurate speech transcription using your selected speech provider.",
            )
            FeatureHighlightRow(
                icon        = Icons.Default.AutoAwesome,
                title       = "AI Enhancements",
                description = "Grammar correction, professional rewrites, summaries & action items",
            )
            FeatureHighlightRow(
                icon        = Icons.Default.CloudSync,
                title       = "Cloud Sync",
                description = "Your recordings backed up and restored across devices automatically",
            )
        }

        // CTA
        Column(
            modifier            = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            if (errorMessage != null) {
                Text(
                    text      = errorMessage,
                    style     = MaterialTheme.typography.bodySmall,
                    color     = MaterialTheme.colorScheme.error,
                    textAlign = TextAlign.Center,
                    modifier  = Modifier.fillMaxWidth(),
                )
                Spacer(Modifier.height(4.dp))
            }

            Button(
                onClick         = onGoogleSignInClick,
                enabled         = !isLoading,
                modifier        = Modifier.fillMaxWidth(),
                shape           = RoundedCornerShape(16.dp),
                colors          = ButtonDefaults.buttonColors(containerColor = Primary),
                contentPadding  = PaddingValues(vertical = 14.dp),
            ) {
                if (isLoading) {
                    CircularProgressIndicator(
                        modifier    = Modifier.size(20.dp),
                        strokeWidth = 2.dp,
                        color       = Color.White,
                    )
                    Spacer(Modifier.width(10.dp))
                    Text(
                        text       = "Signing in…",
                        style      = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.Bold,
                    )
                } else {
                    Text(
                        text       = "Sign in with Google",
                        style      = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }

            TextButton(
                onClick  = onSkipClick,
                enabled  = !isLoading,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(
                    text  = "Skip",
                    style = MaterialTheme.typography.labelLarge,
                    color = OnSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun FeatureHighlightRow(icon: ImageVector, title: String, description: String) {
    Card(
        shape    = RoundedCornerShape(16.dp),
        colors   = CardDefaults.cardColors(containerColor = CardColor),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier              = Modifier.padding(14.dp),
            verticalAlignment     = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Box(
                modifier         = Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .background(Primary.copy(alpha = 0.12f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector        = icon,
                    contentDescription = null,
                    tint               = Primary,
                    modifier           = Modifier.size(20.dp),
                )
            }
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text       = title,
                    style      = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    text  = description,
                    style = MaterialTheme.typography.bodySmall,
                    color = OnSurfaceVariant,
                )
            }
        }
    }
}

