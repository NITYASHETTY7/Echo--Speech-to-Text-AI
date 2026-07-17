package com.echo.dictation.data.repository

import com.echo.dictation.domain.model.AuthState
import com.echo.dictation.domain.model.User
import com.echo.dictation.domain.repository.AuthConfig
import com.echo.dictation.domain.repository.AuthRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Auth is gone. The Flask OTP / Cognito flow has been removed along with the backend.
 *
 * The app now operates in perpetual "dev" mode (exactly what the Flask backend did
 * when no Cognito was configured: g.user_id = 'dev-user'). A synthetic local user
 * is immediately signed in so all callers of [currentUser] continue to work without
 * any changes.
 *
 * Every method that previously contacted the Flask local-auth endpoints is
 * now a no-op or returns a fixed success. The signatures are preserved so no callers
 * need to change.
 */
@Singleton
class AuthRepositoryImpl @Inject constructor() : AuthRepository {

    private val localUser = User(id = "local", email = "local@device")

    private val _authState = MutableStateFlow<AuthState>(AuthState.SignedIn(localUser))
    override val authState: StateFlow<AuthState> = _authState.asStateFlow()

    private val _currentUser = MutableStateFlow<User?>(localUser)
    override val currentUser: StateFlow<User?> = _currentUser.asStateFlow()

    /** No server - return a fixed "dev" auth config. */
    override suspend fun config(): Result<AuthConfig> =
        Result.success(AuthConfig(mode = "dev", region = "", userPoolId = "", clientId = ""))

    /** No OTP server - return success immediately. */
    override suspend fun sendOtp(email: String): Result<String> =
        Result.success("dev mode - no OTP required")

    /** No OTP server - auto-verify and return the local user. */
    override suspend fun verifyOtp(email: String, otp: String): Result<User> =
        Result.success(localUser)

    /** No JWT - return a constant non-null placeholder so null-checks pass. */
    override suspend fun token(): String? = "dev-token"

    /** Logout is a no-op - there is nothing to sign out from. */
    override suspend fun logout() {}
}
