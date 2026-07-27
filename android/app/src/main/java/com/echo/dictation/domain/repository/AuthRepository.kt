package com.echo.dictation.domain.repository

import com.echo.dictation.domain.model.User
import kotlinx.coroutines.flow.StateFlow

interface AuthRepository {
    val currentUser: StateFlow<User?>
    val isAuthenticated: StateFlow<Boolean>
    suspend fun signInWithGoogleIdToken(idToken: String): Result<User>
    suspend fun signOut(): Result<Unit>
}
