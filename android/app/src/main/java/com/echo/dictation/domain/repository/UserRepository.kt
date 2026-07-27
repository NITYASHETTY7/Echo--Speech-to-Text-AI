package com.echo.dictation.domain.repository

import com.echo.dictation.domain.model.User

interface UserRepository {
    suspend fun syncUserProfile(user: User): Result<Unit>
    suspend fun getUserProfile(uid: String): Result<User?>
}
