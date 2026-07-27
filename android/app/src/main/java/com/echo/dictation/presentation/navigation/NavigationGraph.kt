package com.echo.dictation.presentation.navigation

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.platform.LocalContext
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import com.echo.dictation.data.local.AppPreferences
import com.echo.dictation.presentation.ui.MainScreen
import com.echo.dictation.presentation.ui.SettingsScreen
import com.echo.dictation.presentation.ui.auth.AuthUiState
import com.echo.dictation.presentation.ui.auth.AuthViewModel
import com.echo.dictation.presentation.ui.auth.WelcomeOnboardingScreen

object Routes {
    const val ONBOARDING = "onboarding"
    const val MAIN       = "main"
    const val SETTINGS   = "settings"
}

@Composable
fun NavigationGraph(navController: NavHostController) {
    val context = LocalContext.current
    val prefs = AppPreferences(context)
    val startDest = if (prefs.onboardingCompleted) Routes.MAIN else Routes.ONBOARDING

    NavHost(navController, startDestination = startDest) {
        composable(Routes.ONBOARDING) {
            val authViewModel: AuthViewModel = hiltViewModel()
            val uiState by authViewModel.uiState.collectAsStateWithLifecycle()

            // Navigate to MAIN only after successful Firebase authentication
            LaunchedEffect(uiState) {
                if (uiState is AuthUiState.Authenticated) {
                    prefs.onboardingCompleted = true
                    navController.navigate(Routes.MAIN) {
                        popUpTo(Routes.ONBOARDING) { inclusive = true }
                    }
                }
            }

            WelcomeOnboardingScreen(
                uiState = uiState,
                onGoogleSignInClick = {
                    authViewModel.signInWithGoogle(context)
                },
                onSkipClick = {
                    prefs.onboardingCompleted = true
                    navController.navigate(Routes.MAIN) {
                        popUpTo(Routes.ONBOARDING) { inclusive = true }
                    }
                },
            )
        }
        composable(Routes.MAIN) {
            MainScreen(
                onNavigateToSettings = { navController.navigate(Routes.SETTINGS) }
            )
        }
        composable(Routes.SETTINGS) {
            SettingsScreen(
                onBack = { navController.popBackStack() }
            )
        }
    }
}
