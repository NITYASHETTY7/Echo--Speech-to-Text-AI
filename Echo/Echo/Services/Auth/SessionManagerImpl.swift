//
//  SessionManagerImpl.swift
//  Echo
//
//  Concrete session manager.
//  - Bootstraps from persisted FirebaseAuth state on init (survives cold-start).
//  - Attaches an AuthStateDidChangeListener for live observation.
//  - Exposes ownerUid and isAnonymous convenience accessors.
//
//  Firebase is imported ONLY in this file — never in EchoCore or Views.
//

import Foundation
import Combine
import EchoCore
import FirebaseAuth
import os

// MARK: - SessionManagerImpl

final class SessionManagerImpl: SessionManager, @unchecked Sendable {

    // MARK: - Private state

    private let _user = CurrentValueSubject<EchoUser?, Never>(nil)
    private var authListenerHandle: AuthStateDidChangeListenerHandle?
    private let logger = Logger(subsystem: "com.echo.app", category: "SessionManager")

    // MARK: - SessionManager conformance

    var currentUser: EchoUser? { _user.value }

    var userPublisher: AnyPublisher<EchoUser?, Never> {
        _user.eraseToAnyPublisher()
    }

    var isAuthenticated: Bool { _user.value != nil }

    var isAuthenticatedPublisher: AnyPublisher<Bool, Never> {
        _user.map { $0 != nil }.eraseToAnyPublisher()
    }

    /// The Firebase UID for signed-in users; nil for guests.
    /// Use `ownerUid ?? "local"` for storage keys.
    var ownerUid: String? { _user.value?.uid }

    /// True when no user is signed in (guest mode).
    var isAnonymous: Bool { _user.value == nil }

    func setCurrentUser(_ user: EchoUser?) {
        _user.send(user)
        logger.debug("setCurrentUser uid=\(user?.uid ?? "nil", privacy: .public)")
    }

    func clearSession() {
        _user.send(nil)
        logger.debug("clearSession()")
    }

    // MARK: - Init

    init() {
        // Bootstrap from FirebaseAuth's persisted on-disk session.
        // This ensures uid is non-nil immediately on cold-start without a network round-trip.
        if let firebaseUser = Auth.auth().currentUser {
            _user.send(firebaseUser.toEchoUser())
            logger.debug("SessionManagerImpl.init: bootstrapped uid=\(firebaseUser.uid, privacy: .public)")
        } else {
            logger.debug("SessionManagerImpl.init: no persisted Firebase user — guest mode")
        }

        // Stay in sync for the whole process lifetime.
        authListenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            if let user {
                let echoUser = user.toEchoUser()
                self._user.send(echoUser)
                self.logger.debug("AuthStateListener → signed in uid=\(user.uid, privacy: .public)")
            } else {
                self._user.send(nil)
                self.logger.debug("AuthStateListener → signed out")
            }
        }
    }

    deinit {
        if let handle = authListenerHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
}
