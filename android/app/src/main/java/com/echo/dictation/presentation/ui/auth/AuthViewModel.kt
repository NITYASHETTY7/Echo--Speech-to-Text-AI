package com.echo.dictation.presentation.ui.auth

import android.content.Context
import android.util.Log
import androidx.credentials.ClearCredentialStateRequest
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialException
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.echo.dictation.domain.model.User
import com.echo.dictation.domain.repository.AuthRepository
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed interface AuthUiState {
    data object Idle : AuthUiState
    data object Loading : AuthUiState
    data class Authenticated(val user: User) : AuthUiState
    data class Error(val message: String) : AuthUiState
}

@HiltViewModel
class AuthViewModel @Inject constructor(
    private val authRepository: AuthRepository,
) : ViewModel() {

    val currentUser: StateFlow<User?> = authRepository.currentUser
    val isAuthenticated: StateFlow<Boolean> = authRepository.isAuthenticated

    private val _uiState = MutableStateFlow<AuthUiState>(AuthUiState.Idle)
    val uiState: StateFlow<AuthUiState> = _uiState.asStateFlow()

    // ── Sign In ───────────────────────────────────────────────────────────────

    fun signInWithGoogle(context: Context, webClientId: String = "") {
        viewModelScope.launch {
            _uiState.value = AuthUiState.Loading
            try {
                val credentialManager = CredentialManager.create(context)

                // Web client ID (type 3, "server client") from google-services.json
                val clientId = webClientId.ifBlank {
                    "940458102434-50c3uactb5okbu85r9ppoir4hpkoqeg2.apps.googleusercontent.com"
                }

                Log.d(TAG, "signInWithGoogle — clientId=${clientId.take(20)}…")
                ShaFingerprintLogger.logSigningCertificate(context)

                // ── Phase 1: try previously-authorised accounts (fast path) ──────
                // filterByAuthorizedAccounts(true) only shows accounts the user has
                // already granted access to this app. This is the preferred flow
                // (fewer clicks, less friction). It fails with NoCredentialException
                // when no eligible account exists yet — that's not an error.
                val result = tryGetCredential(
                    context           = context,
                    credentialManager = credentialManager,
                    clientId          = clientId,
                    filterAuthorized  = true,
                ) ?: run {
                    // ── Phase 2: show full account picker (first-time / new account) ──
                    Log.d(TAG, "No pre-authorized account — showing full account picker")
                    tryGetCredential(
                        context           = context,
                        credentialManager = credentialManager,
                        clientId          = clientId,
                        filterAuthorized  = false,
                    )
                }

                if (result == null) {
                    // Both phases produced no credential (user dismissed the picker)
                    _uiState.value = AuthUiState.Idle
                    return@launch
                }

                val credential = result.credential
                if (credential is CustomCredential &&
                    credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL
                ) {
                    val googleIdTokenCredential = GoogleIdTokenCredential.createFrom(credential.data)
                    val idToken = googleIdTokenCredential.idToken

                    authRepository.signInWithGoogleIdToken(idToken)
                        .onSuccess { user -> _uiState.value = AuthUiState.Authenticated(user) }
                        .onFailure { ex ->
                            Log.e(TAG, "Firebase sign-in failed", ex)
                            _uiState.value = AuthUiState.Error(
                                ex.message ?: "Firebase authentication failed"
                            )
                        }
                } else {
                    Log.e(TAG, "Unexpected credential type: ${credential.type}")
                    _uiState.value = AuthUiState.Error("Unsupported credential type returned")
                }

            } catch (e: GetCredentialException) {
                val userMessage = translateCredentialError(e)
                Log.e(TAG, "GetCredentialException — type=${e.type} message=${e.message}", e)
                _uiState.value = AuthUiState.Error(userMessage)
            } catch (e: Exception) {
                Log.e(TAG, "Unexpected Google Sign-In error", e)
                _uiState.value = AuthUiState.Error("Sign-in failed. Please try again.")
            }
        }
    }

    /**
     * Attempts one Credential Manager request.  Returns null without throwing
     * when the request produces no credential (no eligible accounts, user
     * dismissed the picker) — the caller decides what to do next.
     *
     * Only propagates [GetCredentialException] for hard failures (misconfiguration,
     * network error, etc.) so the call-site can translate them to user messages.
     */
    private suspend fun tryGetCredential(
        context: Context,
        credentialManager: CredentialManager,
        clientId: String,
        filterAuthorized: Boolean,
    ): androidx.credentials.GetCredentialResponse? {
        return try {
            val option = GetGoogleIdOption.Builder()
                .setFilterByAuthorizedAccounts(filterAuthorized)
                .setServerClientId(clientId)
                .setAutoSelectEnabled(filterAuthorized)   // auto-select only on the fast path
                .build()

            val request = GetCredentialRequest.Builder()
                .addCredentialOption(option)
                .build()

            credentialManager.getCredential(context = context, request = request)
        } catch (e: GetCredentialException) {
            // NoCredentialException (type "android.credentials.GetCredentialException.TYPE_NO_CREDENTIAL")
            // is normal when filterAuthorized=true and no previous sessions exist.
            // All other exception types should propagate.
            val isNoCredential = e.type.contains("NO_CREDENTIAL", ignoreCase = true)
            val isCancelled    = e.type.contains("CANCELLED", ignoreCase = true) ||
                                 e.type.contains("INTERRUPTED", ignoreCase = true)
            when {
                isNoCredential && filterAuthorized -> {
                    Log.d(TAG, "No pre-authorized accounts — will show full picker")
                    null
                }
                isCancelled -> {
                    Log.d(TAG, "User dismissed the credential picker")
                    null   // return null → caller sets state to Idle (not Error)
                }
                else -> throw e   // re-throw hard failures
            }
        }
    }

    /**
     * Translates [GetCredentialException] into a user-friendly message.
     *
     * Error 10 from the Google Play Services One Tap layer is always caused by
     * a SHA-1 certificate fingerprint mismatch — the fingerprint in Firebase
     * Console / Google Cloud Console does not match the certificate that signed
     * the installed APK.  We surface a clear, actionable developer message for
     * debug builds and a generic "try again" message for release.
     */
    private fun translateCredentialError(e: GetCredentialException): String {
        val rawMessage = e.message ?: ""

        return when {
            // Error 10 = Developer console not set up correctly = SHA-1 mismatch
            rawMessage.contains(": 10:") || rawMessage.contains("10:") && rawMessage.contains("Developer console") -> {
                Log.e(TAG,
                    "╔══ GOOGLE SIGN-IN ERROR 10 (SHA-1 MISMATCH) ══════════════════════════\n" +
                    "║ The APK's signing certificate SHA-1 is NOT registered in Firebase.\n" +
                    "║\n" +
                    "║ CURRENTLY REGISTERED in google-services.json:\n" +
                    "║   26:D4:7B:81:D3:EE:99:67:54:34:9A:CB:89:EC:CA:FC:03:69:AE:B3  (Abhishek)\n" +
                    "║   3C:F9:1D:E1:87:01:CE:A1:9F:B5:14:A5:A1:81:AB:53:AB:08:6D:7F  (Narendra)\n" +
                    "║\n" +
                    "║ DIAGNOSIS: Run  gradlew signingReport  and compare the SHA-1 shown\n" +
                    "║ against the values above. If a new machine is being used, register\n" +
                    "║ its SHA-1 in Firebase Console → Project Settings → Android App.\n" +
                    "║\n" +
                    "║ SIGNING CONFIG: local.properties → debug.keystore.path\n" +
                    "║ Currently pinned to C:\\Users\\Abhishek\\.android\\debug.keystore\n" +
                    "╚═══════════════════════════════════════════════════════════════════════"
                )
                "Sign-in is not configured for this device. " +
                "Please contact support or rebuild the app. (SHA-1 mismatch)"
            }

            rawMessage.contains("CANCELED") || rawMessage.contains("CANCELLED") ->
                "Sign-in was cancelled."

            rawMessage.contains("network", ignoreCase = true) ||
            rawMessage.contains("NETWORK", ignoreCase = false) ->
                "No internet connection. Please check your network and try again."

            rawMessage.contains("interrupted", ignoreCase = true) ->
                "Sign-in was interrupted. Please try again."

            else -> {
                Log.e(TAG, "Unrecognised credential error: $rawMessage")
                "Google Sign-In failed. Please try again."
            }
        }
    }

    // ── Sign Out ──────────────────────────────────────────────────────────────

    /**
     * Signs out of Firebase and clears the stored Google credential so the
     * account picker always appears on the next sign-in attempt.
     * onboardingCompleted is intentionally NOT cleared — the user stays on
     * the main screen but in a signed-out state.
     */
    fun signOut(context: Context) {
        viewModelScope.launch {
            // 1. Sign out of Firebase + clear session
            authRepository.signOut()
            // 2. Clear the cached Google credential so Credential Manager
            //    prompts account selection next time instead of auto-selecting
            runCatching {
                val credentialManager = CredentialManager.create(context)
                credentialManager.clearCredentialState(ClearCredentialStateRequest())
            }.onFailure { Log.w(TAG, "clearCredentialState failed (non-fatal)", it) }

            _uiState.value = AuthUiState.Idle
        }
    }

    // ── Utilities ─────────────────────────────────────────────────────────────

    fun clearError() {
        _uiState.value = AuthUiState.Idle
    }

    companion object {
        private const val TAG = "AuthViewModel"
    }
}
