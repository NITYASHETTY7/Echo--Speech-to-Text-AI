//
//  AuthRepositoryImpl.swift
//  Echo
//
//  Concrete AuthRepository. Delegates auth to AuthRemoteDataSource, manages session,
//  and triggers cloud history restore after sign-in.
//

import Foundation
import Combine
import EchoCore
import os

// MARK: - AuthRepositoryImpl

@MainActor
final class AuthRepositoryImpl: AuthRepository, @unchecked Sendable {

    private let remoteDataSource: any AuthRemoteDataSource
    private let sessionManager: any SessionManager
    var onSignedIn: ((EchoUser) async -> Void)?

    private let logger = Logger(subsystem: "com.echo.app", category: "AuthRepository")

    // MARK: - AuthRepository

    var currentUser: EchoUser? { sessionManager.currentUser }

    var currentUserPublisher: AnyPublisher<EchoUser?, Never> {
        sessionManager.userPublisher
    }

    var isAuthenticated: Bool { sessionManager.isAuthenticated }

    // MARK: - Init

    init(
        remoteDataSource: any AuthRemoteDataSource,
        sessionManager: any SessionManager
    ) {
        self.remoteDataSource = remoteDataSource
        self.sessionManager = sessionManager

        if let persisted = remoteDataSource.getCurrentUser() {
            logger.debug("AuthRepositoryImpl.init: cold-start session for uid=\(persisted.uid, privacy: .public)")
            sessionManager.setCurrentUser(persisted)
            Task { [weak self] in await self?.onSignedIn?(persisted) }
        } else {
            logger.debug("AuthRepositoryImpl.init: no persisted session — guest mode")
        }
    }

    // MARK: - Sign In

    func signInWithGoogleTokens(idToken: String, accessToken: String) async -> Result<EchoUser, Error> {
        logger.debug("signInWithGoogleTokens: called")
        let result = await remoteDataSource.signInWithGoogleTokens(idToken: idToken, accessToken: accessToken)
        switch result {
        case .success(let user):
            logger.debug("signInWithGoogleTokens: success uid=\(user.uid, privacy: .public)")
            sessionManager.setCurrentUser(user)
            Task { [weak self] in await self?.onSignedIn?(user) }
        case .failure(let error):
            logger.error("signInWithGoogleTokens: failed — \(error.localizedDescription, privacy: .public)")
        }
        return result
    }

    // MARK: - Sign Out

    func signOut() async -> Result<Void, Error> {
        logger.debug("signOut: called")
        let result = await remoteDataSource.signOut()
        sessionManager.clearSession()
        logger.debug("signOut: session cleared (local history preserved)")
        return result
    }
}
