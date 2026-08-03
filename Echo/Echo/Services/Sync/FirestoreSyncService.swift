//
//  FirestoreSyncService.swift
//  Echo
//
//  Concrete implementation of CloudSyncProtocol using Firestore.
//  Mirrors Android's SyncManagerImpl exactly:
//
//  Collection layout (FLAT top-level — matches Android exactly):
//    transcripts/{transcriptionId}          — all fields + ownerUid
//    transcriptVersions/{versionId}         — all fields + ownerUid
//    userPreferences/{uid}                  — user settings
//
//  Key behaviours:
//  - ownerUid stored in every document (allows single-equality Firestore query)
//  - Local "local" userId rows back-filled to real UID before upload
//  - uploadPendingTranscriptions + uploadPendingVersions run on sign-in and foreground
//  - restoreHistory: no time filter — always recovers full history after reinstall
//  - Network reachability via NWPathMonitor
//  - Retry: failed uploads stay PENDING; retried automatically on next triggerSync()
//  - stopSync() cancels in-flight work; called on sign-out
//
//  Firebase is imported ONLY here. EchoCore never imports Firebase.
//

import Foundation
import Combine
import Network
import EchoCore
import FirebaseFirestore
import FirebaseAuth
import os

// MARK: - FirestoreSyncService

@MainActor
final class FirestoreSyncService: CloudSyncProtocol, @unchecked Sendable {

    // ── Constants (match Android exactly) ────────────────────────────────────
    private enum Collections {
        static let transcripts   = "transcripts"
        static let versions      = "transcriptVersions"
        static let preferences   = "userPreferences"
    }

    // ── Dependencies ──────────────────────────────────────────────────────────
    private let store: any TranscriptionStoreProtocol
    private let sessionManager: any SessionManager
    private let logger = Logger(subsystem: "com.echo.app", category: "CloudSync")

    // ── Firestore (lazy — guard prevents use before configure()) ─────────────
    private var db: Firestore? {
        try? Firestore.firestore()
    }

    // ── Sync state ────────────────────────────────────────────────────────────
    // nonisolated(unsafe) allows the CurrentValueSubject to be read from
    // nonisolated contexts without a MainActor hop. Thread safety is guaranteed
    // because CurrentValueSubject's value property is already protected by a lock
    // internally, and all mutations happen on the MainActor.
    nonisolated(unsafe) private let _syncState   = CurrentValueSubject<SyncState, Never>(.idle)
    nonisolated(unsafe) private let _isOnline    = CurrentValueSubject<Bool, Never>(false)

    nonisolated var syncState: SyncState { _syncState.value }
    nonisolated var syncStatePublisher: AnyPublisher<SyncState, Never> { _syncState.eraseToAnyPublisher() }
    nonisolated var isOnline: Bool { _isOnline.value }
    nonisolated var isOnlinePublisher: AnyPublisher<Bool, Never> { _isOnline.eraseToAnyPublisher() }

    // ── Cancellation ──────────────────────────────────────────────────────────
    private var syncTask: Task<Void, Never>?
    private var monitor: NWPathMonitor?
    private var isStopped = false

    // MARK: - Init

    init(store: any TranscriptionStoreProtocol, sessionManager: any SessionManager) {
        self.store = store
        self.sessionManager = sessionManager
        startNetworkMonitor()
    }

    // MARK: - CloudSyncProtocol

    func triggerSync() async {
        guard !isStopped else { return }
        guard let uid = resolveOwnerUid() else {
            logger.debug("triggerSync: no authenticated user — skipping")
            _syncState.send(.idle)
            return
        }
        guard _isOnline.value else {
            _syncState.send(.offline)
            return
        }
        guard db != nil else {
            logger.error("triggerSync: Firestore unavailable")
            _syncState.send(.failed(message: "Firestore unavailable"))
            return
        }
        _syncState.send(.syncing)
        logger.debug("triggerSync: starting for uid=\(uid, privacy: .public)")
        await backfillLocalRows(uid: uid)
        await uploadPendingTranscriptions()
        await uploadPendingVersions()
        _syncState.send(.success(lastSyncedAt: Date()))
        logger.debug("triggerSync: complete")
    }

    func uploadPendingTranscriptions() async {
        guard !isStopped, let uid = resolveOwnerUid(), let db else { return }
        let pending: [Transcription]
        do { pending = try store.fetchPendingSync() } catch { return }
        guard !pending.isEmpty else { return }

        logger.debug("uploadPendingTranscriptions: \(pending.count) pending")
        for item in pending {
            // Field shape MUST match the deployed Firestore security rules
            // (transcripts.transcriptFieldsValid): required keys include
            // `syncVersion` (int) and `updatedAt` (int). A previous version
            // omitted `syncVersion` and wrote `updatedAt` as a serverTimestamp
            // (a Timestamp, not an int), so keys().hasAll(...) and the
            // `updatedAt is int` assertion both failed → "Missing or
            // insufficient permissions". epoch-ms Int matches Android's Long.
            var doc: [String: Any] = [
                "ownerUid"   : uid,
                "id"         : item.id,
                "text"       : item.text,
                "timestamp"  : item.timestamp,
                "model"      : item.model,
                "audioPath"  : item.audioPath as Any,
                "userId"     : uid,
                "isFavorite" : item.isFavorite,
                "isPinned"   : item.isPinned,
                "syncVersion": 1,
                "deleted"    : false,
                "updatedAt"  : item.updatedAt,
            ]
            // Persist the raw spoken-language transcript so Android and other
            // devices can also show it in the Original tab.
            if let raw = item.rawTranscript {
                doc["rawTranscript"] = raw
            }
            if let lang = item.detectedLanguage {
                doc["detectedLanguage"] = lang
            }
            do {
                try await db.collection(Collections.transcripts)
                    .document(item.id)
                    .setData(doc, merge: true)
                try store.setSyncStatus(id: item.id, status: .synced)
                logger.debug("  uploaded transcription \(item.id, privacy: .public)")
            } catch {
                logger.error("  FAILED to upload \(item.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                // Leave as PENDING — retried on next triggerSync()
            }
        }
    }

    func uploadPendingVersions() async {
        guard !isStopped, let uid = resolveOwnerUid(), let db else { return }
        let pending: [TranscriptVersion]
        do { pending = try store.fetchPendingVersionSync() } catch { return }
        guard !pending.isEmpty else { return }

        logger.debug("uploadPendingVersions: \(pending.count) pending")
        for version in pending {
            let metaJson: String
            if let data = try? JSONEncoder().encode(version.metadata),
               let s = String(data: data, encoding: .utf8) { metaJson = s } else { metaJson = "{}" }

            // Field shape MUST match the deployed Firestore security rules
            // (transcriptVersions.versionFieldsValid): required keys include
            // `syncVersion` (int) and `updatedAt` (int). The previous write
            // omitted `syncVersion` and used a serverTimestamp for `updatedAt`,
            // which failed both keys().hasAll(...) and `updatedAt is int` →
            // the "Missing or insufficient permissions" error in the logs.
            let doc: [String: Any] = [
                "ownerUid"     : uid,
                "id"           : version.id,
                "transcriptId" : version.transcriptId,
                "versionType"  : version.versionType.rawValue,
                "createdAt"    : version.createdAt,
                "provider"     : version.provider,
                "model"        : version.model,
                "content"      : version.content,
                "metadataJson" : metaJson,
                "syncVersion"  : 1,
                "deleted"      : false,
                "updatedAt"    : Int64(Date().timeIntervalSince1970 * 1000),
            ]
            do {
                try await db.collection(Collections.versions)
                    .document(version.id)
                    .setData(doc, merge: true)
                try store.setVersionSyncStatus(id: version.id, status: .synced)
                logger.debug("  uploaded version \(version.id, privacy: .public)")
            } catch {
                logger.error("  FAILED version \(version.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func restoreHistory() async {
        guard !isStopped, let uid = resolveOwnerUid(), let db else {
            logger.warning("restoreHistory: aborted — no user or Firestore unavailable")
            return
        }
        guard _isOnline.value else {
            logger.warning("restoreHistory: offline — will retry when network returns")
            return
        }
        _syncState.send(.syncing)
        logger.debug("restoreHistory: starting full restore for uid=\(uid, privacy: .public)")

        do {
            // ── Step 1: Fetch all transcriptions ─────────────────────────────
            let txSnap = try await db.collection(Collections.transcripts)
                .whereField("ownerUid", isEqualTo: uid)
                .getDocuments()

            var restoredIDs: [String] = []
            for doc in txSnap.documents {
                let isDeleted = doc.data()["deleted"] as? Bool ?? false
                if !isDeleted {
                    mergeRemoteTranscription(doc: doc, uid: uid)
                    restoredIDs.append(doc.documentID)
                }
            }
            logger.debug("restoreHistory: merged \(restoredIDs.count) transcripts")

            // ── Step 2: Fetch matching versions ───────────────────────────────
            // Single equality filter on ownerUid avoids composite index requirement.
            // Client-side filter by transcriptId (mirrors Android implementation).
            if !restoredIDs.isEmpty {
                let wanted = Set(restoredIDs)
                let verSnap = try await db.collection(Collections.versions)
                    .whereField("ownerUid", isEqualTo: uid)
                    .getDocuments()

                var mergedVersions = 0
                for doc in verSnap.documents {
                    let transcriptId = doc.data()["transcriptId"] as? String ?? ""
                    if wanted.contains(transcriptId) {
                        mergeRemoteVersion(doc: doc)
                        mergedVersions += 1
                    }
                }
                logger.debug("restoreHistory: merged \(mergedVersions) versions")
            }

            _syncState.send(.success(lastSyncedAt: Date()))
            logger.debug("restoreHistory: COMPLETE for uid=\(uid, privacy: .public)")
        } catch {
            let msg = error.localizedDescription
            _syncState.send(.failed(message: msg))
            logger.error("restoreHistory: FAILED — \(msg, privacy: .public)")
        }
    }

    func stopSync() {
        isStopped = true
        syncTask?.cancel()
        syncTask = nil
        monitor?.cancel()
        monitor = nil
        _syncState.send(.idle)
        logger.debug("stopSync: sync stopped")
    }

    // MARK: - Private helpers

    /// Resolves the authenticated UID, checking FirebaseAuth first (survives
    /// process death), then falling back to the in-memory session.
    /// Mirrors Android's SyncManagerImpl.resolveOwnerUid() exactly.
    private func resolveOwnerUid() -> String? {
        if let fbUid = Auth.auth().currentUser?.uid { return fbUid }
        return sessionManager.ownerUid
    }

    /// Re-tags rows written with userId = "local" before auth resolved.
    /// Mirrors Android's SyncManagerImpl.backfillLocalRows().
    private func backfillLocalRows(uid: String) async {
        guard let all = try? store.fetch(limit: 10_000) else { return }
        let orphans = all.filter { $0.userId == "local" }
        guard !orphans.isEmpty else { return }
        logger.warning("backfillLocalRows: re-tagging \(orphans.count) orphaned rows → uid=\(uid, privacy: .public)")
        for var t in orphans {
            t = Transcription(id: t.id, text: t.text, timestamp: t.timestamp,
                              model: t.model, audioPath: t.audioPath, userId: uid,
                              synced: false, duration: t.duration,
                              isFavorite: t.isFavorite, isPinned: t.isPinned,
                              syncStatus: .pending)
            try? store.update(t)
        }
    }

    /// Upserts a remote transcription into local store.
    /// Remote wins on tie (updatedAt >=). Mirrors Android's mergeRemoteTranscription().
    private func mergeRemoteTranscription(doc: QueryDocumentSnapshot, uid: String) {
        let data       = doc.data()
        let remoteId   = doc.documentID
        let text       = data["text"]      as? String ?? ""
        let timestamp  = data["timestamp"] as? Int64  ?? 0
        let model      = data["model"]     as? String ?? ""
        let audioPath  = data["audioPath"] as? String
        let isFavorite = data["isFavorite"] as? Bool ?? false
        let isPinned   = data["isPinned"]   as? Bool ?? false

        // rawTranscript: prefer remote value; fall back to text for legacy records
        // that predate this field. This preserves the spoken-language original.
        let remoteRaw  = data["rawTranscript"] as? String
        let remoteLang = data["detectedLanguage"] as? String

        // Read updatedAt from the remote document (epoch ms Int64).
        let remoteUpdatedMs: Int64
        if let ms = data["updatedAt"] as? Int64 {
            remoteUpdatedMs = ms
        } else if let n = data["updatedAt"] as? NSNumber {
            remoteUpdatedMs = n.int64Value
        } else if let ts = data["updatedAt"] as? Timestamp {
            remoteUpdatedMs = Int64(ts.seconds) * 1000
        } else {
            remoteUpdatedMs = timestamp
        }

        // Dedup: if a newer local version exists, don't overwrite.
        if let existing = try? store.fetch(id: remoteId) {
            let localUpdatedMs = existing.updatedAt   // epoch ms
            if remoteUpdatedMs < localUpdatedMs { return }
        }

        let transcription = Transcription(
            id: remoteId, text: text, timestamp: timestamp,
            model: model, audioPath: audioPath, userId: uid,
            synced: true, isFavorite: isFavorite, isPinned: isPinned,
            syncStatus: .synced,
            updatedAt: remoteUpdatedMs,
            // Protect the Original: use remoteRaw if available, otherwise keep
            // existing local rawTranscript so sync never erases a spoken-language original.
            rawTranscript: remoteRaw,
            detectedLanguage: remoteLang
        )
        if let existing = try? store.fetch(id: remoteId), existing.rawTranscript != nil {
            // Preserve existing rawTranscript — it must never be overwritten.
            // The update path in TranscriptionStore is write-once for rawTranscript.
            try? store.update(transcription)
        } else {
            try? store.insert(transcription)
            // If already exists, update to pick up remote values.
            try? store.update(transcription)
        }
    }

    /// Upserts a remote version into local store.
    private func mergeRemoteVersion(doc: QueryDocumentSnapshot) {
        let data         = doc.data()
        let verId        = doc.documentID
        let transcriptId = data["transcriptId"] as? String ?? ""
        let rawType      = data["versionType"]  as? String ?? "Custom"
        let createdAt    = data["createdAt"]    as? Int64  ?? 0
        let provider     = data["provider"]     as? String ?? ""
        let model        = data["model"]        as? String ?? ""
        let content      = data["content"]      as? String ?? ""
        let metaJson     = data["metadataJson"] as? String ?? "{}"

        let metadata: [String: String]
        if let d = metaJson.data(using: .utf8),
           let dict = try? JSONDecoder().decode([String: String].self, from: d) {
            metadata = dict
        } else { metadata = [:] }

        let version = TranscriptVersion(
            id: verId, transcriptId: transcriptId,
            versionType: VersionType(rawValue: rawType) ?? .custom,
            createdAt: createdAt, provider: provider, model: model,
            content: content, metadata: metadata, syncStatus: .synced
        )
        try? store.insertVersion(version)
    }

    // MARK: - Network monitoring

    private func startNetworkMonitor() {
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let online = path.status == .satisfied
            Task { @MainActor in
                self._isOnline.send(online)
                if online {
                    self.logger.debug("Network available — triggering sync")
                    await self.triggerSync()
                } else {
                    self._syncState.send(.offline)
                    self.logger.debug("Network lost — sync paused")
                }
            }
        }
        m.start(queue: DispatchQueue(label: "com.echo.app.network"))
        monitor = m
        // Synchronous initial check
        _isOnline.send(m.currentPath.status == .satisfied)
    }
}
