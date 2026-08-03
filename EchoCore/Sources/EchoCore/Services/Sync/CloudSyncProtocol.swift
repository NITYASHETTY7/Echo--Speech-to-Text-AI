//
//  CloudSyncProtocol.swift
//  EchoCore
//
//  Firebase-free protocol defining cloud sync operations.
//  Mirrors Android's domain.sync.SyncManager interface.
//  Concrete implementation (FirestoreSyncService) lives in the app target.
//

import Foundation
import Combine

// MARK: - SyncState

/// Mirrors Android's domain.sync.SyncState sealed interface.
public enum SyncState: Equatable, Sendable {
    case idle
    case syncing
    case success(lastSyncedAt: Date)
    case failed(message: String)
    case offline
}

// MARK: - CloudSyncProtocol

public protocol CloudSyncProtocol: AnyObject, Sendable {

    /// Current sync state observable.
    var syncState: SyncState { get }
    var syncStatePublisher: AnyPublisher<SyncState, Never> { get }

    /// Whether the device currently has network connectivity.
    var isOnline: Bool { get }
    var isOnlinePublisher: AnyPublisher<Bool, Never> { get }

    /// Full sync cycle: upload pending changes + download remote updates.
    func triggerSync() async

    /// Upload all locally PENDING transcriptions to Firestore.
    func uploadPendingTranscriptions() async

    /// Upload all locally PENDING versions to Firestore.
    func uploadPendingVersions() async

    /// Full history restore — downloads ALL records for the signed-in user.
    /// Call after sign-in to recover history after reinstall.
    func restoreHistory() async

    /// Stop all sync operations and clear queued work.
    /// Called on sign-out.
    func stopSync()
}
