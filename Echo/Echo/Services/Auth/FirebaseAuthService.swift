//
//  FirebaseAuthService.swift
//  Echo
//
//  Concrete AuthRemoteDataSource backed by FirebaseAuth.
//  Firebase is imported ONLY here — EchoCore remains Firebase-free.
//

import Foundation
import EchoCore
import FirebaseAuth
import os

// MARK: - FirebaseAuthService

final class FirebaseAuthService: AuthRemoteDataSource, @unchecked Sendable {

    private let logger = Logger(subsystem: "com.echo.app", category: "FirebaseAuthService")

    // MARK: - AuthRemoteDataSource

    func getCurrentUser() -> EchoUser? {
        Auth.auth().currentUser?.toEchoUser()
    }

    func signInWithGoogleTokens(idToken: String, accessToken: String) async -> Result<EchoUser, Error> {
        do {
            // GoogleAuthProvider.credential requires both the ID token AND the
            // OAuth2 access token. Passing an empty accessToken causes Firebase
            // to silently reject the credential in some configurations.
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: accessToken
            )
            let result = try await Auth.auth().signIn(with: credential)
            let echoUser = result.user.toEchoUser()
            logger.debug("signInWithGoogleTokens: success uid=\(echoUser.uid, privacy: .public)")
            return .success(echoUser)
        } catch {
            logger.error("signInWithGoogleTokens: failed — \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }

    func signOut() async -> Result<Void, Error> {
        do {
            try Auth.auth().signOut()
            logger.debug("signOut: success")
            return .success(())
        } catch {
            logger.error("signOut: failed — \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }
}
// toEchoUser() is defined in FirebaseUserMapper.swift
