package com.echo.dictation.data.remote.datasource

import com.echo.dictation.domain.model.User

interface UserRemoteDataSource {
    suspend fun createOrUpdateUser(user: User): Result<Unit>
    suspend fun getUser(uid: String): Result<User?>
}
