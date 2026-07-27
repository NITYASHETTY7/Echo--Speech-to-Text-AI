package com.echo.dictation.data.remote.firebase

import android.util.Log
import com.echo.dictation.data.remote.datasource.AuthRemoteDataSource
import com.echo.dictation.domain.model.User
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.GoogleAuthProvider
import kotlinx.coroutines.tasks.await
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class FirebaseAuthService @Inject constructor() : AuthRemoteDataSource {

    private val auth: FirebaseAuth? get() = runCatching { FirebaseAuth.getInstance() }.getOrNull()

    override fun getCurrentUser(): User? {
        val firebaseUser = auth?.currentUser ?: return null
        return User(
            uid = firebaseUser.uid,
            displayName = firebaseUser.displayName ?: firebaseUser.email?.substringBefore("@"),
            email = firebaseUser.email,
            photoUrl = firebaseUser.photoUrl?.toString(),
            createdAt = firebaseUser.metadata?.creationTimestamp ?: System.currentTimeMillis(),
            lastLogin = firebaseUser.metadata?.lastSignInTimestamp ?: System.currentTimeMillis(),
        )
    }

    override suspend fun signInWithGoogleIdToken(idToken: String): Result<User> = runCatching {
        val firebaseAuth = auth ?: throw IllegalStateException("Firebase Auth is not initialized.")
        val credential = GoogleAuthProvider.getCredential(idToken, null)
        val authResult = firebaseAuth.signInWithCredential(credential).await()
        val firebaseUser = authResult.user ?: throw IllegalStateException("Google sign-in succeeded but returned null user")

        User(
            uid = firebaseUser.uid,
            displayName = firebaseUser.displayName ?: firebaseUser.email?.substringBefore("@"),
            email = firebaseUser.email,
            photoUrl = firebaseUser.photoUrl?.toString(),
            createdAt = firebaseUser.metadata?.creationTimestamp ?: System.currentTimeMillis(),
            lastLogin = System.currentTimeMillis(),
        )
    }.onFailure { Log.e(TAG, "signInWithGoogleIdToken failed", it) }

    override suspend fun signOut(): Result<Unit> = runCatching {
        auth?.signOut()
        Unit
    }

    companion object {
        private const val TAG = "FirebaseAuthService"
    }
}
