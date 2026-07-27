package com.echo.dictation.data.session

import com.echo.dictation.domain.model.User
import com.echo.dictation.domain.session.SessionManager
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SessionManagerImpl @Inject constructor() : SessionManager {

    private val _currentUser = MutableStateFlow<User?>(null)
    override val currentUser: StateFlow<User?> = _currentUser.asStateFlow()

    private val _isAuthenticated = MutableStateFlow(false)
    override val isAuthenticated: StateFlow<Boolean> = _isAuthenticated.asStateFlow()

    override fun setCurrentUser(user: User?) {
        _currentUser.value = user
        _isAuthenticated.value = user != null
    }

    override fun clearSession() {
        _currentUser.value = null
        _isAuthenticated.value = false
    }
}
