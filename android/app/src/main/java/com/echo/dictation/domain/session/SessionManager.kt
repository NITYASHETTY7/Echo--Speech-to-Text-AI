package com.echo.dictation.domain.session

import com.echo.dictation.domain.model.User
import kotlinx.coroutines.flow.StateFlow

/**
 * Single source of session state across the application.
 * Manages user login state, persistence, and logout without requiring repeated queries.
 */
interface SessionManager {
    val currentUser: StateFlow<User?>
    val isAuthenticated: StateFlow<Boolean>
    fun setCurrentUser(user: User?)
    fun clearSession()
}
