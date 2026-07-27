package com.echo.dictation.data.repository

import com.echo.dictation.data.remote.datasource.UserRemoteDataSource
import com.echo.dictation.domain.model.User
import com.echo.dictation.domain.repository.UserRepository
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class UserRepositoryImpl @Inject constructor(
    private val userRemoteDataSource: UserRemoteDataSource,
) : UserRepository {

    override suspend fun syncUserProfile(user: User): Result<Unit> =
        userRemoteDataSource.createOrUpdateUser(user)

    override suspend fun getUserProfile(uid: String): Result<User?> =
        userRemoteDataSource.getUser(uid)
}
