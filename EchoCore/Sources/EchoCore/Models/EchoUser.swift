//
//  EchoUser.swift
//  EchoCore
//
//  Domain model for an authenticated user.
//  Mirrors Android's domain.model.User data class exactly.
//
//  Named EchoUser (not User) to avoid collisions with system types.
//  Firebase never appears here — this is pure domain.
//

import Foundation

public struct EchoUser: Equatable, Sendable {
    public let uid: String
    public let displayName: String?
    public let email: String?
    public let photoURL: String?
    public let createdAt: Int64     // Unix epoch milliseconds
    public let lastLogin: Int64     // Unix epoch milliseconds

    public init(
        uid: String,
        displayName: String? = nil,
        email: String? = nil,
        photoURL: String? = nil,
        createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1_000),
        lastLogin: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
    ) {
        self.uid = uid
        self.displayName = displayName
        self.email = email
        self.photoURL = photoURL
        self.createdAt = createdAt
        self.lastLogin = lastLogin
    }

    /// Convenience: display name falling back to the email prefix.
    public var resolvedDisplayName: String {
        if let name = displayName, !name.isEmpty { return name }
        if let email, let prefix = email.split(separator: "@").first {
            return String(prefix)
        }
        return "User"
    }
}
