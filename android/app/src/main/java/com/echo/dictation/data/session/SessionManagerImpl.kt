package com.echo.dictation.data.session

import android.util.Log
import com.echo.dictation.domain.model.User
import com.echo.dictation.domain.session.SessionManager
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseUser
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Single source of truth for the signed-in user.
 *
 * ## Why this class bootstraps itself from FirebaseAuth
 *
 * Previously the session was populated ONLY by `AuthRepositoryImpl.init {}`.
 * `AuthRepositoryImpl` is a lazily-created `@Singleton`, and its only injector was
 * `AuthViewModel`, which is only constructed on the ONBOARDING route and in
 * SettingsScreen.  Once `prefs.onboardingCompleted == true` the app starts directly
 * at `Routes.MAIN`, so `AuthViewModel` was never created, `AuthRepositoryImpl` was
 * never instantiated, its `init {}` never ran, and this flow stayed `null` forever —
 * even though `FirebaseAuth` had a perfectly valid persisted user on disk.
 *
 * That single fact caused:
 *  - every transcription to be saved with `userId = "local"`,
 *  - `SyncManagerImpl.uploadPendingChanges()` to abort at its null-user guard
 *    (so the `transcripts` collection was never created),
 *  - `SyncManagerImpl.restoreRecentHistory()` to abort at the same guard,
 *  - the history Flow to filter on the wrong userId.
 *
 * `FirebaseAuth.currentUser` IS persisted across process death by the Firebase SDK,
 * so reading it here at construction time makes the session correct on every launch
 * with no dependency on which screen happens to be showing.
 */
@Singleton
class SessionManagerImpl @Inject constructor() : SessionManager {

    private val _currentUser = MutableStateFlow<User?>(null)
    override val currentUser: StateFlow<User?> = _currentUser.asStateFlow()

    private val _isAuthenticated = MutableStateFlow(false)
    override val isAuthenticated: StateFlow<Boolean> = _isAuthenticated.asStateFlow()

    private val auth: FirebaseAuth?
        get() = runCatching { FirebaseAuth.getInstance() }.getOrNull()

    init {
        // ── Bootstrap from the persisted FirebaseAuth session ──────────────────
        val persisted = runCatching { auth?.currentUser }.getOrNull()
        if (persisted != null) {
            _currentUser.value = persisted.toDomain()
            _isAuthenticated.value = true
            Log.d(DIAG, "SessionManagerImpl.init: bootstrapped session from FirebaseAuth " +
                    "uid=${persisted.uid} email=${persisted.email}")
        } else {
            Log.d(DIAG, "SessionManagerImpl.init: no persisted FirebaseAuth user")
        }

        // ── Stay in sync for the whole process lifetime ────────────────────────
        // Covers sign-in, sign-out, and token refresh performed anywhere in the app.
        runCatching {
            auth?.addAuthStateListener { firebaseAuth ->
                val user = firebaseAuth.currentUser
                if (user != null) {
                    _currentUser.value = user.toDomain()
                    _isAuthenticated.value = true
                    Log.d(DIAG, "SessionManagerImpl.AuthStateListener: session → uid=${user.uid}")
                } else {
                    _currentUser.value = null
                    _isAuthenticated.value = false
                    Log.d(DIAG, "SessionManagerImpl.AuthStateListener: session cleared")
                }
            }
        }.onFailure {
            Log.e(DIAG, "SessionManagerImpl.init: failed to attach AuthStateListener", it)
        }
    }

    override fun setCurrentUser(user: User?) {
        _currentUser.value = user
        _isAuthenticated.value = user != null
        Log.d(DIAG, "SessionManagerImpl.setCurrentUser(uid=${user?.uid ?: "NULL"})")
    }

    override fun clearSession() {
        _currentUser.value = null
        _isAuthenticated.value = false
        Log.d(DIAG, "SessionManagerImpl.clearSession()")
    }

    private fun FirebaseUser.toDomain(): User = User(
        uid         = uid,
        displayName = displayName ?: email?.substringBefore("@"),
        email       = email,
        photoUrl    = photoUrl?.toString(),
        createdAt   = metadata?.creationTimestamp ?: System.currentTimeMillis(),
        lastLogin   = metadata?.lastSignInTimestamp ?: System.currentTimeMillis(),
    )

    companion object {
        private const val DIAG = "CloudSync"
    }
}
