//
//  AuthRepository.swift
//  EchoCore
//
//  Repository protocol for authentication operations. Firebase-free.
//

import Foundation
import Combine

// MARK: - AuthRepository

public protocol AuthRepository: AnyObject, Sendable {
    var currentUser: EchoUser? { get }
    var currentUserPublisher: AnyPublisher<EchoUser?, Never> { get }
    var isAuthenticated: Bool { get }

    /// Authenticates with tokens obtained from Google Sign-In.
    ///
    /// - Parameters:
    ///   - idToken: `GIDGoogleUser.idToken.tokenString`
    ///   - accessToken: `GIDGoogleUser.accessToken.tokenString`
    func signInWithGoogleTokens(idToken: String, accessToken: String) async -> Result<EchoUser, Error>

    func signOut() async -> Result<Void, Error>
}
