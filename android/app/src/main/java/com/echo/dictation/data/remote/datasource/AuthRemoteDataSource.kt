package com.echo.dictation.data.remote.datasource

import com.echo.dictation.domain.model.User

interface AuthRemoteDataSource {
    fun getCurrentUser(): User?
    suspend fun signInWithGoogleIdToken(idToken: String): Result<User>
    suspend fun signOut(): Result<Unit>
}
