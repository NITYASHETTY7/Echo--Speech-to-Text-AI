package com.echo.dictation.presentation.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.echo.dictation.domain.model.AuthState
import com.echo.dictation.domain.repository.AuthRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class AuthViewModel @Inject constructor(private val repository: AuthRepository) : ViewModel() {
    val state: StateFlow<AuthState> = repository.authState
    fun sendOtp(email: String, onSent: (String) -> Unit, onError: (String) -> Unit) = viewModelScope.launch { repository.sendOtp(email).onSuccess(onSent).onFailure { onError(it.message ?: "Unable to send OTP") } }
    fun verifyOtp(email: String, otp: String, onSuccess: () -> Unit, onError: (String) -> Unit) = viewModelScope.launch { repository.verifyOtp(email, otp).onSuccess { onSuccess() }.onFailure { onError(it.message ?: "Authentication failed") } }
    fun logout() = viewModelScope.launch { repository.logout() }
}
