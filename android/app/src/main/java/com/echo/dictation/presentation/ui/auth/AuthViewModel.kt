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

                // Web client ID (type 3) from google-services.json — project echo-mirai
                val clientId = webClientId.ifBlank {
                    "940458102434-50c3uactb5okbu85r9ppoir4hpkoqeg2.apps.googleusercontent.com"
                }

                val googleIdOption = GetGoogleIdOption.Builder()
                    .setFilterByAuthorizedAccounts(false)
                    .setServerClientId(clientId)
                    .setAutoSelectEnabled(false)
                    .build()

                val request = GetCredentialRequest.Builder()
                    .addCredentialOption(googleIdOption)
                    .build()

                val result = credentialManager.getCredential(context = context, request = request)
                val credential = result.credential

                if (credential is CustomCredential &&
                    credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL
                ) {
                    val googleIdTokenCredential = GoogleIdTokenCredential.createFrom(credential.data)
                    val idToken = googleIdTokenCredential.idToken

                    authRepository.signInWithGoogleIdToken(idToken)
                        .onSuccess { user -> _uiState.value = AuthUiState.Authenticated(user) }
                        .onFailure { ex ->
                            _uiState.value = AuthUiState.Error(
                                ex.message ?: "Firebase authentication failed"
                            )
                        }
                } else {
                    _uiState.value = AuthUiState.Error("Unsupported credential type returned")
                }
            } catch (e: GetCredentialException) {
                Log.e(TAG, "Google Sign-In CredentialException", e)
                _uiState.value = AuthUiState.Error("Google Sign-In cancelled or failed: ${e.message}")
            } catch (e: Exception) {
                Log.e(TAG, "Unexpected Google Sign-In error", e)
                _uiState.value = AuthUiState.Error("Sign-in error: ${e.message}")
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
