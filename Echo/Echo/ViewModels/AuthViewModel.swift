//
//  AuthViewModel.swift
//  Echo
//
//  Presentation ViewModel for authentication.
//  Google Sign-In SDK 9.x: both idToken and accessToken are extracted from the
//  result and passed to AuthRepository.
//
//  Sign-out fix (three-part):
//
//  1. `currentUser` is now a STORED `@Observable`-tracked property.
//     The previous version exposed it as a computed property delegating to
//     `authRepository.currentUser` — an `any AuthRepository` existential.
//     SwiftUI's `@Observable` access tracking cannot follow through existentials,
//     so mutations to SessionManagerImpl._user never caused a view re-render.
//
//  2. A Combine subscription to `authRepository.currentUserPublisher` keeps the
//     stored property in sync whenever Firebase's AuthStateDidChangeListener
//     fires (sign-in AND sign-out).  This covers both the async sign-in path and
//     the rare case where another device or a token expiry triggers sign-out.
//
//  3. `signOut()` resets `preferences.onboardingCompleted = false` so that
//     `RootView` (which gates on `preferences.onboardingCompleted`) routes back
//     to `WelcomeView` immediately — matching the dev-reset behaviour.
//

import Foundation
import SwiftUI
import EchoCore
import Combine
import GoogleSignIn
import os

// MARK: - AuthViewModel

@MainActor
@Observable
final class AuthViewModel {

    // MARK: - Observable state
    //
    // `currentUser` is a STORED property, not a computed passthrough.
    // @Observable tracks access to stored properties; it cannot track access
    // through an existential (any AuthRepository), so the previous computed-
    // property approach silently broke reactive updates on sign-out.

    private(set) var uiState: AuthUiState = .idle
    private(set) var currentUser: EchoUser?

    var isAuthenticated: Bool { currentUser != nil }

    // MARK: - Dependencies

    private let authRepository: any AuthRepository
    private let preferences: Preferences
    private let logger = Logger(subsystem: "com.echo.app", category: "AuthViewModel")

    // Retain the Combine subscription for its lifetime.
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(authRepository: any AuthRepository, preferences: Preferences) {
        self.authRepository = authRepository
        self.preferences    = preferences

        // Seed initial state from whatever the session manager already knows.
        let initial = authRepository.currentUser
        self.currentUser = initial
        self.uiState = initial.map { .authenticated($0) } ?? .idle

        // Subscribe to the publisher so every future Firebase auth-state change
        // (sign-in from another device, token expiry, explicit sign-out) flows
        // through here and triggers an @Observable invalidation.
        authRepository.currentUserPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] user in
                guard let self else { return }
                self.currentUser = user
                // If the publisher emits nil (sign-out) but uiState still shows
                // authenticated, reset it.
                if user == nil, case .authenticated = self.uiState {
                    self.uiState = .idle
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Google Sign-In

    func signInWithGoogle(presenting viewController: UIViewController) {
        // Only block if a sign-in is already in flight (.loading).
        // Do NOT block when uiState == .authenticated — a user can be presented
        // with WelcomeView immediately after signOut() resets the state, and a
        // stale .authenticated value (from a Combine delivery race) must not
        // silently drop the tap.
        guard uiState != .loading else { return }
        uiState = .loading

        Task {
            do {
                let result = try await GIDSignIn.sharedInstance.signIn(
                    withPresenting: viewController
                )

                guard let idToken = result.user.idToken?.tokenString else {
                    uiState = .error("Google Sign-In returned no ID token.")
                    logger.error("signInWithGoogle: idToken is nil")
                    return
                }

                let accessToken = result.user.accessToken.tokenString

                logger.debug("signInWithGoogle: got tokens, passing to AuthRepository")
                let authResult = await authRepository.signInWithGoogleTokens(
                    idToken: idToken,
                    accessToken: accessToken
                )

                switch authResult {
                case .success(let user):
                    currentUser = user
                    uiState = .authenticated(user)
                    logger.debug("signInWithGoogle: authenticated uid=\(user.uid, privacy: .public)")
                case .failure(let error):
                    uiState = .error(error.localizedDescription)
                    logger.error("signInWithGoogle: auth failed — \(error.localizedDescription, privacy: .public)")
                }

            } catch let gidError as GIDSignInError where gidError.code == .canceled {
                uiState = .idle
                logger.debug("signInWithGoogle: cancelled by user")
            } catch {
                uiState = .error("Sign-in failed: \(error.localizedDescription)")
                logger.error("signInWithGoogle: unexpected error — \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Sign Out

    func signOut() {
        // Reset local state SYNCHRONOUSLY before the async Task so:
        //  1. Any view reading `currentUser` or `uiState` sees nil/.idle immediately.
        //  2. The guard in signInWithGoogle (uiState != .loading) cannot fire
        //     in a stale-authenticated state if the user taps sign-in extremely quickly.
        //  3. No timing window exists where uiState == .authenticated after the
        //     sign-out intent has been expressed.
        currentUser = nil
        uiState     = .idle

        Task {
            // Sign out of Google — clears the cached Google profile/token.
            GIDSignIn.sharedInstance.signOut()

            // Sign out of Firebase — triggers AuthStateDidChangeListener
            // → SessionManagerImpl.clearSession() → currentUserPublisher emits nil
            // → Combine sink re-confirms currentUser = nil (idempotent, harmless).
            _ = await authRepository.signOut()

            // Return to Welcome screen after async sign-out completes, so
            // session is fully cleared before the onboarding gate is lowered.
            preferences.onboardingCompleted = false

            logger.debug("signOut: complete")
        }
    }

    func clearError() {
        uiState = .idle
    }
}
