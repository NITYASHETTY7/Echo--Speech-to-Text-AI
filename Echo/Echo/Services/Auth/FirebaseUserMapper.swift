//
//  FirebaseUserMapper.swift
//  Echo
//
//  Single source of truth for mapping FirebaseAuth.User → EchoUser.
//  Eliminates the duplicate private extensions that were in both
//  FirebaseAuthService.swift and SessionManagerImpl.swift.
//
//  Internal access — used only within the Echo app target.
//  Firebase is imported here; EchoCore never imports this file.
//

import FirebaseAuth
import EchoCore

extension FirebaseAuth.User {
    /// Maps a FirebaseAuth user to the domain model.
    /// Timestamps are converted from seconds to milliseconds to match
    /// the Android implementation which uses System.currentTimeMillis().
    func toEchoUser() -> EchoUser {
        EchoUser(
            uid: uid,
            displayName: displayName ?? email?.components(separatedBy: "@").first,
            email: email,
            photoURL: photoURL?.absoluteString,
            createdAt: Int64(
                (metadata.creationDate?.timeIntervalSince1970 ?? Date().timeIntervalSince1970) * 1_000
            ),
            lastLogin: Int64(
                (metadata.lastSignInDate?.timeIntervalSince1970 ?? Date().timeIntervalSince1970) * 1_000
            )
        )
    }
}
