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
        /**
         * Cold-start: Firebase Auth may still hold a valid token from before the
         * reinstall (tokens are stored in the device KeyStore, which survives
         * uninstall on API 23+).
         *
         * If a user is already authenticated, restore their recent history
         * immediately so the History screen is populated without requiring
         * a new sign-in gesture.
         */
        val initialUser = authRemoteDataSource.getCurrentUser()
        if (initialUser != null) {
            Log.d(TAG, "Cold-start: session restored for ${initialUser.uid}")
            sessionManager.setCurrentUser(initialUser)
            authScope.launch {
                Log.d(TAG, "Cold-start: triggering history restoration for ${initialUser.uid}")
                syncManager.restoreRecentHistory()
                    .onFailure { ex ->
                        Log.w(TAG, "Cold-start restore failed (non-fatal): ${ex.message}")
                    }
            }
        }
    }

    override suspend fun signInWithGoogleIdToken(idToken: String): Result<User> {
        val result = authRemoteDataSource.signInWithGoogleIdToken(idToken)
        result.onSuccess { user ->
            // 1. Update Firestore user profile
            userRemoteDataSource.createOrUpdateUser(user)
            // 2. Mark session as authenticated
            sessionManager.setCurrentUser(user)
            // 3. Restore recent history in the background (non-blocking)
            //    setCurrentUser() is synchronous — user.uid is available to
            //    restoreRecentHistory() when the coroutine body executes.
            authScope.launch {
                Log.d(TAG, "Sign-in: triggering history restoration for ${user.uid}")
                syncManager.restoreRecentHistory()
                    .onFailure { ex ->
                        Log.w(TAG, "Sign-in restore failed (non-fatal): ${ex.message}")
                    }
            }
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
