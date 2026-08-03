//
//  AuthUiState.swift
//  EchoCore
//
//  Presentation-layer state machine for the authentication flow.
//  Mirrors Android's presentation.ui.auth.AuthUiState sealed interface.
//

import Foundation

// MARK: - AuthUiState

public enum AuthUiState: Equatable, Sendable {
    /// Initial / reset state. No active operation.
    case idle
    /// Google Sign-In is in progress (credential fetch + Firebase exchange).
    case loading
    /// Sign-in succeeded; the user is now authenticated.
    case authenticated(EchoUser)
    /// An error occurred; message is user-readable.
    case error(String)

    public static func == (lhs: AuthUiState, rhs: AuthUiState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.loading, .loading): return true
        case (.authenticated(let a), .authenticated(let b)): return a == b
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}
