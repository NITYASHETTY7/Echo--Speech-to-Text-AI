//
//  DataModelV2Tests.swift
//  EchoTests
//
//  Unit tests for the Group 1 V2 data model additions:
//  - SyncStatus enum
//  - VersionType enum
//  - TranscriptVersion model
//  - Transcription V2 fields (isFavorite, isPinned, syncStatus)
//  - TranscriptionStore V2 methods (setFavorite, setPin, setSyncStatus,
//    fetchPendingSync, insertVersion, fetchVersions, deleteVersions)
//

import SwiftData
import Testing
@testable import Echo
import EchoCore

// MARK: - SyncStatus Tests

struct SyncStatusTests {

    @Test("SyncStatus raw values match Android constants")
    func rawValues() {
        #expect(SyncStatus.pending.rawValue   == "PENDING")
        #expect(SyncStatus.synced.rawValue    == "SYNCED")
        #expect(SyncStatus.localOnly.rawValue == "LOCAL_ONLY")
        #expect(SyncStatus.failed.rawValue    == "FAILED")
    }

    @Test("SyncStatus round-trips through Codable")
    func codableRoundTrip() throws {
        for status in [SyncStatus.pending, .synced, .localOnly, .failed] {
            let data = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(SyncStatus.self, from: data)
            #expect(decoded == status)
        }
    }
}

// MARK: - VersionType Tests

struct VersionTypeTests {

    @Test("VersionType raw values match Android VersionType enum names")
    func rawValues() {
        #expect(VersionType.original.rawValue         == "Original")
        #expect(VersionType.grammarCorrected.rawValue == "GrammarCorrected")
        #expect(VersionType.autoEnhanced.rawValue     == "AutoEnhanced")
        #expect(VersionType.professional.rawValue     == "Professional")
        #expect(VersionType.summary.rawValue          == "Summary")
        #expect(VersionType.meetingNotes.rawValue     == "MeetingNotes")
        #expect(VersionType.email.rawValue            == "Email")
        #expect(VersionType.bulletPoints.rawValue     == "BulletPoints")
        #expect(VersionType.translation.rawValue      == "Translation")
        #expect(VersionType.custom.rawValue           == "Custom")
    }

    @Test("VersionType display names are non-empty")
    func displayNames() {
        for type_ in VersionType.allCases {
            #expect(!type_.displayName.isEmpty)
        }
    }

    @Test("Only original is not AI-generated")
    func isAIGenerated() {
        #expect(!VersionType.original.isAIGenerated)
        for type_ in VersionType.allCases where type_ != .original {
            #expect(type_.isAIGenerated)
        }
    }

    @Test("VersionType round-trips through Codable")
    func codableRoundTrip() throws {
        for type_ in VersionType.allCases {
            let data = try JSONEncoder().encode(type_)
            let decoded = try JSONDecoder().decode(VersionType.self, from: data)
            #expect(decoded == type_)
        }
    }
}

// MARK: - TranscriptVersion Tests

struct TranscriptVersionTests {

    @Test("TranscriptVersion creates with correct defaults")
    func defaultInit() {
        let version = TranscriptVersion(
            transcriptId: "t1",
            versionType: .professional,
            provider: "Groq",
            model: "llama-3.3-70b-versatile",
            content: "Professional rewrite"
        )
        #expect(version.transcriptId == "t1")
        #expect(version.versionType == .professional)
        #expect(version.content == "Professional rewrite")
        #expect(version.metadata.isEmpty)
        #expect(!version.id.isEmpty)
    }

    @Test("TranscriptVersion date derived from createdAt milliseconds")
    func dateConversion() {
        let ts: Int64 = 1_700_000_000_000  // some fixed epoch ms
        let version = TranscriptVersion(
            transcriptId: "t2",
            versionType: .summary,
            createdAt: ts,
            provider: "OpenAI",
            model: "gpt-4o",
            content: "Summary"
        )
        let expected = Date(timeIntervalSince1970: TimeInterval(ts) / 1_000)
        #expect(abs(version.date.timeIntervalSince(expected)) < 0.001)
    }
}

// MARK: - Transcription V2 Field Tests

struct TranscriptionV2FieldTests {

    @Test("Transcription defaults isFavorite/isPinned to false, syncStatus to .pending")
    func v2Defaults() {
        let t = Transcription(
            id: "t1", text: "hello", timestamp: 1000,
            model: "m", userId: "u"
        )
        #expect(t.isFavorite == false)
        #expect(t.isPinned == false)
        #expect(t.syncStatus == .pending)
    }

    @Test("Transcription preserves explicit V2 field values")
    func v2ExplicitValues() {
        let t = Transcription(
            id: "t1", text: "hi", timestamp: 1000, model: "m", userId: "u",
            isFavorite: true, isPinned: true, syncStatus: .synced
        )
        #expect(t.isFavorite == true)
        #expect(t.isPinned == true)
        #expect(t.syncStatus == .synced)
    }
}

// MARK: - TranscriptionStore V2 Tests

struct TranscriptionStoreV2Tests {

    private func makeTranscription(id: String, timestamp: Int64 = 1000) -> Transcription {
        Transcription(id: id, text: "test", timestamp: timestamp, model: "m", userId: "u")
    }

    @Test("setFavorite persists and round-trips correctly")
    func setFavorite() async throws {
        try await MainActor.run {
            let container = try TranscriptionStore.makeModelContainer(inMemory: true)
            let store = TranscriptionStore(modelContext: container.mainContext)

            try store.insert(makeTranscription(id: "fav"))
            try store.setFavorite(id: "fav", value: true)

            let fetched = try store.fetch(id: "fav")
            #expect(fetched?.isFavorite == true)

            try store.setFavorite(id: "fav", value: false)
            #expect(try store.fetch(id: "fav")?.isFavorite == false)
        }
    }

    @Test("setPin persists and round-trips correctly")
    func setPin() async throws {
        try await MainActor.run {
            let container = try TranscriptionStore.makeModelContainer(inMemory: true)
            let store = TranscriptionStore(modelContext: container.mainContext)

            try store.insert(makeTranscription(id: "pin"))
            try store.setPin(id: "pin", value: true)

            let fetched = try store.fetch(id: "pin")
            #expect(fetched?.isPinned == true)
        }
    }

    @Test("Pinned items sort before unpinned in fetch()")
    func pinnedSortOrder() async throws {
        try await MainActor.run {
            let container = try TranscriptionStore.makeModelContainer(inMemory: true)
            let store = TranscriptionStore(modelContext: container.mainContext)

            try store.insert(makeTranscription(id: "a", timestamp: 300))
            try store.insert(makeTranscription(id: "b", timestamp: 200))
            try store.insert(makeTranscription(id: "c", timestamp: 100))

            // Pin the oldest item — it should now sort first.
            try store.setPin(id: "c", value: true)

            let order = try store.fetch().map(\.id)
            #expect(order.first == "c")
        }
    }

    @Test("setSyncStatus updates status and synced flag")
    func setSyncStatus() async throws {
        try await MainActor.run {
            let container = try TranscriptionStore.makeModelContainer(inMemory: true)
            let store = TranscriptionStore(modelContext: container.mainContext)

            try store.insert(makeTranscription(id: "sync"))

            try store.setSyncStatus(id: "sync", status: .synced)
            let synced = try store.fetch(id: "sync")
            #expect(synced?.syncStatus == .synced)
            #expect(synced?.synced == true)

            try store.setSyncStatus(id: "sync", status: .failed)
            let failed = try store.fetch(id: "sync")
            #expect(failed?.syncStatus == .failed)
            #expect(failed?.synced == false)
        }
    }

    @Test("fetchPendingSync returns only PENDING items")
    func fetchPendingSync() async throws {
        try await MainActor.run {
            let container = try TranscriptionStore.makeModelContainer(inMemory: true)
            let store = TranscriptionStore(modelContext: container.mainContext)

            try store.insert(makeTranscription(id: "p1"))
            try store.insert(makeTranscription(id: "p2"))
            try store.setSyncStatus(id: "p1", status: .synced)

            let pending = try store.fetchPendingSync()
            #expect(pending.map(\.id) == ["p2"])
        }
    }

    @Test("Versions insert, fetch, and delete correctly")
    func versionCRUD() async throws {
        try await MainActor.run {
            let container = try TranscriptionStore.makeModelContainer(inMemory: true)
            let store = TranscriptionStore(modelContext: container.mainContext)

            let version = TranscriptVersion(
                id: "v1",
                transcriptId: "t1",
                versionType: .professional,
                provider: "Groq",
                model: "llama-3.3-70b-versatile",
                content: "Professional version"
            )
            try store.insertVersion(version)

            let fetched = try store.fetchVersions(forTranscriptId: "t1")
            #expect(fetched.count == 1)
            #expect(fetched.first?.content == "Professional version")
            #expect(fetched.first?.versionType == .professional)

            try store.deleteVersions(forTranscriptId: "t1")
            #expect(try store.fetchVersions(forTranscriptId: "t1").isEmpty)
        }
    }

    @Test("Duplicate version IDs are ignored")
    func duplicateVersionIgnored() async throws {
        try await MainActor.run {
            let container = try TranscriptionStore.makeModelContainer(inMemory: true)
            let store = TranscriptionStore(modelContext: container.mainContext)

            let v = TranscriptVersion(id: "dup", transcriptId: "t1", versionType: .summary,
                                      provider: "Groq", model: "m", content: "first")
            try store.insertVersion(v)
            let v2 = TranscriptVersion(id: "dup", transcriptId: "t1", versionType: .summary,
                                       provider: "Groq", model: "m", content: "second")
            try store.insertVersion(v2)

            let all = try store.fetchVersions(forTranscriptId: "t1")
            #expect(all.count == 1)
            #expect(all.first?.content == "first")
        }
    }

    @Test("Versions metadata JSON round-trips correctly")
    func versionMetadataRoundTrip() async throws {
        try await MainActor.run {
            let container = try TranscriptionStore.makeModelContainer(inMemory: true)
            let store = TranscriptionStore(modelContext: container.mainContext)

            let version = TranscriptVersion(
                id: "meta-test",
                transcriptId: "t2",
                versionType: .translation,
                provider: "Groq",
                model: "m",
                content: "Translated",
                metadata: ["target_language": "French"]
            )
            try store.insertVersion(version)

            let fetched = try store.fetchVersions(forTranscriptId: "t2")
            #expect(fetched.first?.metadata["target_language"] == "French")
        }
    }

    @Test("deleteAll removes both transcriptions and versions")
    func deleteAllClearsVersions() async throws {
        try await MainActor.run {
            let container = try TranscriptionStore.makeModelContainer(inMemory: true)
            let store = TranscriptionStore(modelContext: container.mainContext)

            try store.insert(makeTranscription(id: "del1"))
            try store.insertVersion(TranscriptVersion(id: "dv1", transcriptId: "del1",
                versionType: .professional, provider: "Groq", model: "m", content: "x"))

            try store.deleteAll()

            #expect(try store.fetch().isEmpty)
            #expect(try store.fetchVersions(forTranscriptId: "del1").isEmpty)
        }
    }
}
