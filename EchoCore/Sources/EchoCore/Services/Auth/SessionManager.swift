//
//  SessionManager.swift
//  EchoCore
//
//  Single source of truth for authentication session state.
//  Firebase-free — concrete implementation lives in the app target.
//

import Foundation
import Combine

// MARK: - SessionManager

public protocol SessionManager: AnyObject, Sendable {

    // MARK: - Observables

    /// The currently signed-in user, or nil for guest / signed-out.
    var currentUser: EchoUser? { get }
    /// Publisher emitting on every auth state change.
    var userPublisher: AnyPublisher<EchoUser?, Never> { get }

    // MARK: - Derived state

    /// True when a user is signed in.
    var isAuthenticated: Bool { get }
    /// Publisher for isAuthenticated.
    var isAuthenticatedPublisher: AnyPublisher<Bool, Never> { get }

    /// The owner UID to stamp on cloud documents.
    /// Returns the Firebase UID for signed-in users, nil for guests.
    /// Callers should use `ownerUid ?? "local"` for local storage keys.
    var ownerUid: String? { get }

    /// True when no user is signed in (guest / anonymous mode).
    var isAnonymous: Bool { get }

    // MARK: - Mutations

    /// Called by AuthRepository after a successful sign-in.
    func setCurrentUser(_ user: EchoUser?)
    /// Called by AuthRepository after sign-out.
    func clearSession()
}
