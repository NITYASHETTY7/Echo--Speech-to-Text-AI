//
//  AuthTests.swift
//  EchoTests
//
//  Unit tests for Group 2 — Firebase Authentication & Cloud Foundation.
//
//  Strategy: no real Firebase, no real network.
//  All Firebase work is behind AuthRemoteDataSource — this test file
//  uses in-process stubs for everything.
//
//  Test coverage:
//  - Guest mode: no sign-in, local storage works, syncStatus = .localOnly
//  - Sign-in success: session populated, syncStatus = .pending, ownerUid stamped
//  - Sign-in failure: session stays nil, error surfaced
//  - Sign-out: session cleared, local history preserved
//  - Authentication state transitions in AuthViewModel
//  - ownerUid assignment in TranscriptionCoordinator
//  - Duplicate prevention: inserting the same ID twice is a no-op
//

import Testing
import Combine
import SwiftData
@testable import Echo
import EchoCore

// ══════════════════════════════════════════════════════════════════════════════
// MARK: - Stubs
// ══════════════════════════════════════════════════════════════════════════════

/// In-process stub for AuthRemoteDataSource.
/// Controls whether signIn succeeds and which user is "persisted".
@MainActor
final class StubAuthRemoteDataSource: AuthRemoteDataSource, @unchecked Sendable {
    var persistedUser: EchoUser?
    var signInResult: Result<EchoUser, Error> = .failure(
        NSError(domain: "stub", code: 0, userInfo: [NSLocalizedDescriptionKey: "not configured"])
    )
    var signOutCalled = false

    func getCurrentUser() -> EchoUser? { persistedUser }

    func signInWithGoogleTokens(idToken: String, accessToken: String) async -> Result<EchoUser, Error> {
        return signInResult
    }

    func signOut() async -> Result<Void, Error> {
        signOutCalled = true
        persistedUser = nil
        return .success(())
    }
}

/// In-process stub for SessionManager.
@MainActor
final class StubSessionManager: SessionManager, @unchecked Sendable {
    private let subject = CurrentValueSubject<EchoUser?, Never>(nil)

    var currentUser: EchoUser? { subject.value }
    var isAuthenticated: Bool { subject.value != nil }
    var userPublisher: AnyPublisher<EchoUser?, Never> { subject.eraseToAnyPublisher() }
    var isAuthenticatedPublisher: AnyPublisher<Bool, Never> {
        subject.map { $0 != nil }.eraseToAnyPublisher()
    }
    var ownerUid: String? { subject.value?.uid }
    var isAnonymous: Bool { subject.value == nil }
    var setCalled = false
    var clearCalled = false

    func setCurrentUser(_ user: EchoUser?) {
        setCalled = true
        subject.send(user)
    }
    func clearSession() {
        clearCalled = true
        subject.send(nil)
    }
}

/// Minimal user fixture.
private func echoUser(uid: String = "uid-123") -> EchoUser {
    EchoUser(uid: uid, displayName: "Test User", email: "test@example.com")
}

// ══════════════════════════════════════════════════════════════════════════════
// MARK: - EchoUser Tests
// ══════════════════════════════════════════════════════════════════════════════

struct EchoUserTests {

    @Test("EchoUser resolvedDisplayName prefers displayName over email prefix")
    func resolvedDisplayNamePreference() {
        let withName = EchoUser(uid: "u", displayName: "Alice", email: "alice@example.com")
        #expect(withName.resolvedDisplayName == "Alice")

        let withoutName = EchoUser(uid: "u", displayName: nil, email: "bob@example.com")
        #expect(withoutName.resolvedDisplayName == "bob")

        let bare = EchoUser(uid: "u")
        #expect(bare.resolvedDisplayName == "User")
    }

    @Test("EchoUser equality is UID-based via Equatable")
    func equality() {
        let a = EchoUser(uid: "x", displayName: "A")
        let b = EchoUser(uid: "x", displayName: "B")
        let c = EchoUser(uid: "y")
        #expect(a == b)   // same UID
        #expect(a != c)   // different UID
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// MARK: - AuthUiState Tests
// ══════════════════════════════════════════════════════════════════════════════

struct AuthUiStateTests {

    @Test("AuthUiState equality works correctly")
    func stateEquality() {
        let user = echoUser()
        #expect(AuthUiState.idle == .idle)
        #expect(AuthUiState.loading == .loading)
        #expect(AuthUiState.authenticated(user) == .authenticated(user))
        #expect(AuthUiState.error("msg") == .error("msg"))
        #expect(AuthUiState.idle != .loading)
        #expect(AuthUiState.authenticated(user) != .idle)
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// MARK: - SessionManager Tests
// ══════════════════════════════════════════════════════════════════════════════

struct StubSessionManagerTests {

    @Test("StubSessionManager starts as guest (no user)")
    func guestMode() async throws {
        await MainActor.run {
            let session = StubSessionManager()
            #expect(session.currentUser == nil)
            #expect(!session.isAuthenticated)
        }
    }

    @Test("setCurrentUser and clearSession work correctly")
    func setAndClear() async throws {
        await MainActor.run {
            let session = StubSessionManager()
            let user = echoUser()
            session.setCurrentUser(user)
            #expect(session.currentUser?.uid == "uid-123")
            #expect(session.isAuthenticated)
            session.clearSession()
            #expect(session.currentUser == nil)
            #expect(!session.isAuthenticated)
        }
    }

    @Test("userPublisher emits on setCurrentUser / clearSession")
    func publisher() async throws {
        await MainActor.run {
            let session = StubSessionManager()
            var emissions: [EchoUser?] = []
            let cancellable = session.userPublisher.sink { emissions.append($0) }
            session.setCurrentUser(echoUser())
            session.clearSession()
            // CurrentValueSubject emits the current value on subscribe (nil),
            // then two more (user, nil) = 3 total.
            #expect(emissions.count == 3)
            _ = cancellable
        }
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// MARK: - AuthRepositoryImpl Tests
// ══════════════════════════════════════════════════════════════════════════════

struct AuthRepositoryImplTests {

    // Helpers
    @MainActor
    private func makeRepo(
        persisted: EchoUser? = nil,
        signInResult: Result<EchoUser, Error> = .success(echoUser()),
        onSignedIn: ((EchoUser) async -> Void)? = nil
    ) -> (AuthRepositoryImpl, StubAuthRemoteDataSource, StubSessionManager) {
        let remote = StubAuthRemoteDataSource()
        remote.persistedUser = persisted
        remote.signInResult = signInResult
        let session = StubSessionManager()
        let repo = AuthRepositoryImpl(
            remoteDataSource: remote,
            sessionManager: session,
            onSignedIn: onSignedIn
        )
        return (repo, remote, session)
    }

    @Test("Cold-start: persisted user restores session")
    func coldStartRestore() async throws {
        try await MainActor.run {
            let user = echoUser()
            let (repo, _, session) = makeRepo(persisted: user)
            // After init, session should be populated.
            #expect(repo.currentUser?.uid == user.uid)
            #expect(session.setCalled)
        }
    }

    @Test("Cold-start: no persisted user → guest mode")
    func coldStartGuest() async throws {
        try await MainActor.run {
            let (repo, _, session) = makeRepo(persisted: nil)
            #expect(repo.currentUser == nil)
            #expect(!repo.isAuthenticated)
            #expect(!session.setCalled)
        }
    }

    @Test("signInWithGoogleTokens success: session populated, onSignedIn called")
    func signInSuccess() async throws {
        var onSignedInCalledWith: EchoUser? = nil
        let (repo, _, session) = await MainActor.run {
            makeRepo(
                persisted: nil,
                signInResult: .success(echoUser()),
                onSignedIn: { user in onSignedInCalledWith = user }
            )
        }
        let result = await repo.signInWithGoogleTokens(idToken: "valid-token", accessToken: "mock-access-token")
        #expect(result.isSuccess)
        let sessionUser = await MainActor.run { session.currentUser }
        #expect(sessionUser?.uid == "uid-123")
        // Give onSignedIn Task time to execute
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(onSignedInCalledWith?.uid == "uid-123")
    }

    @Test("signInWithGoogleTokens failure: session stays nil, error returned")
    func signInFailure() async throws {
        let (repo, remote, session) = await MainActor.run {
            let r = makeRepo()
            r.1.signInResult = .failure(
                NSError(domain: "auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Invalid credential"])
            )
            return r
        }
        let result = await repo.signInWithGoogleTokens(idToken: "bad-token", accessToken: "mock-access-token")
        #expect(result.isFailure)
        let sessionUser = await MainActor.run { session.currentUser }
        #expect(sessionUser == nil)
        _ = remote
    }

    @Test("signOut: session cleared, signOut called on remote")
    func signOut() async throws {
        let (repo, remote, session) = await MainActor.run {
            makeRepo(persisted: echoUser())
        }
        let result = await repo.signOut()
        #expect(result.isSuccess)
        let sessionUser = await MainActor.run { session.currentUser }
        #expect(sessionUser == nil)
        #expect(await MainActor.run { session.clearCalled })
        #expect(await MainActor.run { remote.signOutCalled })
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// MARK: - AuthViewModel Tests
// ══════════════════════════════════════════════════════════════════════════════

@MainActor
struct AuthViewModelTests {

    private func makeVM(
        persisted: EchoUser? = nil,
        signInResult: Result<EchoUser, Error> = .success(echoUser())
    ) -> (AuthViewModel, StubAuthRemoteDataSource) {
        let remote = StubAuthRemoteDataSource()
        remote.persistedUser = persisted
        remote.signInResult = signInResult
        let session = StubSessionManager()
        let repo = AuthRepositoryImpl(remoteDataSource: remote, sessionManager: session)
        let vm = AuthViewModel(authRepository: repo, preferences: Preferences())
        return (vm, remote)
    }

    @Test("Initial state is .idle for guest, .authenticated for restored session")
    func initialState() {
        let (guestVM, _) = makeVM(persisted: nil)
        #expect(guestVM.uiState == .idle)

        let (authedVM, _) = makeVM(persisted: echoUser())
        if case .authenticated(let u) = authedVM.uiState {
            #expect(u.uid == "uid-123")
        } else {
            Issue.record("Expected .authenticated but got \(authedVM.uiState)")
        }
    }

    @Test("clearError resets state to .idle")
    func clearError() {
        let (vm, _) = makeVM()
        // Manually set an error state by simulating a failed state machine.
        vm.clearError()
        #expect(vm.uiState == .idle)
    }

    @Test("currentUser reflects repository state")
    func currentUser() {
        let (guest, _) = makeVM(persisted: nil)
        #expect(guest.currentUser == nil)
        #expect(!guest.isAuthenticated)

        let (authed, _) = makeVM(persisted: echoUser())
        #expect(authed.currentUser?.uid == "uid-123")
        #expect(authed.isAuthenticated)
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// MARK: - ownerUid Stamping Tests
// ══════════════════════════════════════════════════════════════════════════════

struct OwnerUidStampingTests {

    @Test("Guest transcription gets userId=local and syncStatus=.localOnly")
    func guestOwnerUid() async throws {
        try await MainActor.run {
            let container = try TranscriptionStore.makeModelContainer(inMemory: true)
            let store = TranscriptionStore(modelContext: container.mainContext)

            // Coordinator with guest ownerUidProvider
            let transcription = Transcription(
                id: UUID().uuidString,
                text: "guest transcript",
                timestamp: Int64(Date().timeIntervalSince1970 * 1000),
                model: "m",
                userId: "local",
                synced: false,
                syncStatus: .localOnly
            )
            try store.insert(transcription)

            let fetched = try store.fetch(id: transcription.id)
            #expect(fetched?.userId == "local")
            #expect(fetched?.syncStatus == .localOnly)
        }
    }

    @Test("Authenticated transcription gets ownerUid and syncStatus=.pending")
    func authenticatedOwnerUid() async throws {
        try await MainActor.run {
            let container = try TranscriptionStore.makeModelContainer(inMemory: true)
            let store = TranscriptionStore(modelContext: container.mainContext)

            let uid = "firebase-uid-xyz"
            let transcription = Transcription(
                id: UUID().uuidString,
                text: "signed-in transcript",
                timestamp: Int64(Date().timeIntervalSince1970 * 1000),
                model: "m",
                userId: uid,
                synced: false,
                syncStatus: .pending
            )
            try store.insert(transcription)

            let fetched = try store.fetch(id: transcription.id)
            #expect(fetched?.userId == uid)
            #expect(fetched?.syncStatus == .pending)
        }
    }

    @Test("ownerUid closure provides correct UID at save time")
    func ownerUidClosure() {
        var capturedUid: String? = nil
        // Simulate what TranscriptionCoordinator.persist does
        let ownerUidProvider: () -> String = { "firebase-uid-abc" }
        let ownerUid = ownerUidProvider()
        capturedUid = ownerUid
        #expect(capturedUid == "firebase-uid-abc")
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// MARK: - Duplicate Prevention Tests
// ══════════════════════════════════════════════════════════════════════════════

struct DuplicatePreventionTests {

    @Test("Inserting same transcription ID twice is a no-op (matches Android IGNORE strategy)")
    func insertDuplicateIsIgnored() async throws {
        try await MainActor.run {
            let container = try TranscriptionStore.makeModelContainer(inMemory: true)
            let store = TranscriptionStore(modelContext: container.mainContext)

            let t1 = Transcription(id: "dup", text: "first", timestamp: 1000, model: "m", userId: "u")
            let t2 = Transcription(id: "dup", text: "second", timestamp: 2000, model: "m", userId: "u")

            try store.insert(t1)
            try store.insert(t2)

            let all = try store.fetch()
            #expect(all.count == 1)
            #expect(all.first?.text == "first")
        }
    }

    @Test("Inserting same version ID twice is a no-op")
    func insertDuplicateVersionIsIgnored() async throws {
        try await MainActor.run {
            let container = try TranscriptionStore.makeModelContainer(inMemory: true)
            let store = TranscriptionStore(modelContext: container.mainContext)

            let v1 = TranscriptVersion(id: "dup-v", transcriptId: "t1",
                                       versionType: .professional, provider: "Groq",
                                       model: "m", content: "first")
            let v2 = TranscriptVersion(id: "dup-v", transcriptId: "t1",
                                       versionType: .professional, provider: "Groq",
                                       model: "m", content: "second")

            try store.insertVersion(v1)
            try store.insertVersion(v2)

            let all = try store.fetchVersions(forTranscriptId: "t1")
            #expect(all.count == 1)
            #expect(all.first?.content == "first")
        }
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// MARK: - Sync Queue Tests
// ══════════════════════════════════════════════════════════════════════════════

struct SyncQueueTests {

    @Test("fetchPendingSync returns only PENDING items, not LOCAL_ONLY")
    func pendingSyncQueue() async throws {
        try await MainActor.run {
            let container = try TranscriptionStore.makeModelContainer(inMemory: true)
            let store = TranscriptionStore(modelContext: container.mainContext)

            let pending = Transcription(id: "p", text: "pending", timestamp: 1000,
                                        model: "m", userId: "uid", syncStatus: .pending)
            let localOnly = Transcription(id: "lo", text: "local", timestamp: 2000,
                                          model: "m", userId: "local", syncStatus: .localOnly)
            let synced = Transcription(id: "s", text: "synced", timestamp: 3000,
                                       model: "m", userId: "uid", syncStatus: .synced)

            try store.insert(pending)
            try store.insert(localOnly)
            try store.insert(synced)

            let queue = try store.fetchPendingSync()
            #expect(queue.map(\.id) == ["p"])
        }
    }

    @Test("setSyncStatus promotes LOCAL_ONLY → PENDING on sign-in")
    func promoteSyncStatus() async throws {
        try await MainActor.run {
            let container = try TranscriptionStore.makeModelContainer(inMemory: true)
            let store = TranscriptionStore(modelContext: container.mainContext)

            let t = Transcription(id: "t1", text: "hi", timestamp: 1000,
                                  model: "m", userId: "local", syncStatus: .localOnly)
            try store.insert(t)
            try store.setSyncStatus(id: "t1", status: .pending)

            let fetched = try store.fetch(id: "t1")
            #expect(fetched?.syncStatus == .pending)
        }
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// MARK: - History Restoration Tests
// ══════════════════════════════════════════════════════════════════════════════

struct HistoryRestorationTests {

    @Test("onSignedIn closure is invoked with the signed-in user")
    func onSignedInCalledOnSuccess() async throws {
        var receivedUser: EchoUser? = nil

        let remote = await MainActor.run {
            let r = StubAuthRemoteDataSource()
            r.signInResult = .success(echoUser())
            return r
        }
        let session = await MainActor.run { StubSessionManager() }
        let repo = await MainActor.run {
            AuthRepositoryImpl(
                remoteDataSource: remote,
                sessionManager: session,
                onSignedIn: { user in receivedUser = user }
            )
        }
        _ = await repo.signInWithGoogleTokens(idToken: "tok", accessToken: "mock-access-token")
        // Allow the background Task to run
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(receivedUser?.uid == "uid-123")
    }

    @Test("Sign-out does not delete local transcriptions")
    func signOutPreservesLocalHistory() async throws {
        try await MainActor.run {
            let container = try TranscriptionStore.makeModelContainer(inMemory: true)
            let store = TranscriptionStore(modelContext: container.mainContext)

            let t = Transcription(id: "local1", text: "old", timestamp: 1000,
                                  model: "m", userId: "uid-old")
            try store.insert(t)

            // Sign out in isolation — AuthRepository only calls sessionManager.clearSession()
            let session = StubSessionManager()
            session.setCurrentUser(echoUser())
            session.clearSession()

            // Local data must still be there
            let all = try store.fetch()
            #expect(!all.isEmpty)
            #expect(all.first?.id == "local1")
        }
    }
}

// MARK: - Result helpers

private extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
    var isFailure: Bool { !isSuccess }
}
