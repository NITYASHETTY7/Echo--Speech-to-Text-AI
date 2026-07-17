package com.echo.dictation.presentation.navigation

import androidx.compose.runtime.Composable
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import com.echo.dictation.presentation.ui.MainScreen

object Routes { const val LOGIN = "login"; const val MAIN = "main" }

@Composable
fun NavigationGraph(navController: NavHostController) {
    NavHost(navController, startDestination = Routes.MAIN) {
        composable(Routes.MAIN) { MainScreen() }
    }
}
