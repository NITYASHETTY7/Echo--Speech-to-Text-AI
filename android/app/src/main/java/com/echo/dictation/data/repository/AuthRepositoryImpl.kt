package com.echo.dictation.data.repository

import android.util.Log
import com.echo.dictation.data.remote.datasource.AuthRemoteDataSource
import com.echo.dictation.data.remote.datasource.UserRemoteDataSource
import com.echo.dictation.domain.model.User
import com.echo.dictation.domain.repository.AuthRepository
import com.echo.dictation.domain.session.SessionManager
import com.echo.dictation.domain.sync.SyncManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AuthRepositoryImpl @Inject constructor(
    private val authRemoteDataSource: AuthRemoteDataSource,
    private val userRemoteDataSource: UserRemoteDataSource,
    private val sessionManager: SessionManager,
    private val syncManager: SyncManager,
) : AuthRepository {

    private val authScope = CoroutineScope(Dispatchers.IO)

    override val currentUser: StateFlow<User?> = sessionManager.currentUser
    override val isAuthenticated: StateFlow<Boolean> = sessionManager.isAuthenticated

    init {
        val initialUser = authRemoteDataSource.getCurrentUser()
        Log.d("CloudSync", "AuthRepositoryImpl.init: FirebaseAuth persisted user = ${initialUser?.uid ?: "NULL"}")
        if (initialUser != null) {
            Log.d(TAG, "Cold-start: session restored for ${initialUser.uid}")
            sessionManager.setCurrentUser(initialUser)
            authScope.launch {
                Log.d("CloudSync", "AuthRepositoryImpl.init: cold-start restore starting for uid=${initialUser.uid}")
                syncManager.restoreRecentHistory()
                    .onSuccess { Log.d("CloudSync", "AuthRepositoryImpl.init: cold-start restore SUCCESS") }
                    .onFailure { ex ->
                        Log.e("CloudSync", "AuthRepositoryImpl.init: cold-start restore FAILED — " +
                                "${ex.javaClass.name}: ${ex.message}", ex)
                    }
            }
        } else {
            Log.d("CloudSync", "AuthRepositoryImpl.init: no persisted session — user must sign in")
        }
    }

    override suspend fun signInWithGoogleIdToken(idToken: String): Result<User> {
        Log.d("CloudSync", "AuthRepositoryImpl.signInWithGoogleIdToken: called")
        val result = authRemoteDataSource.signInWithGoogleIdToken(idToken)
        result.onSuccess { user ->
            Log.d("CloudSync", "AuthRepositoryImpl.signInWithGoogleIdToken: SUCCESS uid=${user.uid} email=${user.email}")
            userRemoteDataSource.createOrUpdateUser(user)
            sessionManager.setCurrentUser(user)
            authScope.launch {
                Log.d("CloudSync", "AuthRepositoryImpl: launching restoreRecentHistory for uid=${user.uid}")
                syncManager.restoreRecentHistory()
                    .onSuccess { Log.d("CloudSync", "AuthRepositoryImpl: restoreRecentHistory SUCCESS") }
                    .onFailure { ex ->
                        Log.e("CloudSync", "AuthRepositoryImpl: restoreRecentHistory FAILED — " +
                                "${ex.javaClass.name}: ${ex.message}", ex)
                    }
            }
        }
        result.onFailure { ex ->
            Log.e("CloudSync", "AuthRepositoryImpl.signInWithGoogleIdToken: FAILED — ${ex.javaClass.name}: ${ex.message}", ex)
        }
        return result
    }

    override suspend fun signOut(): Result<Unit> {
        val result = authRemoteDataSource.signOut()
        sessionManager.clearSession()
        return result
    }

    companion object {
        private const val TAG = "AuthRepositoryImpl"
    }
}
