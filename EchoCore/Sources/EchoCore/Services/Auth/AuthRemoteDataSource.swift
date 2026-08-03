//
//  AuthRemoteDataSource.swift
//  EchoCore
//
//  Data-layer port for remote authentication operations.
//  Firebase-free protocol — concrete implementation in app target.
//

import Foundation

// MARK: - AuthRemoteDataSource

public protocol AuthRemoteDataSource: AnyObject, Sendable {
    /// Returns the currently persisted signed-in user, or nil.
    func getCurrentUser() -> EchoUser?

    /// Exchanges Google Sign-In tokens for a Firebase credential and signs in.
    ///
    /// - Parameters:
    ///   - idToken: The OpenID Connect ID token from `GIDGoogleUser.idToken.tokenString`.
    ///   - accessToken: The OAuth2 access token from `GIDGoogleUser.accessToken.tokenString`.
    ///     Required by `GoogleAuthProvider.credential()` in FirebaseAuth 12+.
    func signInWithGoogleTokens(idToken: String, accessToken: String) async -> Result<EchoUser, Error>

    /// Signs out of Firebase.
    func signOut() async -> Result<Void, Error>
}
