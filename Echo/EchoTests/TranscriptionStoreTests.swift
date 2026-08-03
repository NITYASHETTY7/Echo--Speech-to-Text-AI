//
//  TranscriptionStoreTests.swift
//  EchoTests
//
//  TranscriptionStore is @MainActor-isolated (ModelContext must be accessed on
//  the main thread). Swift Testing runs @Test functions as @Sendable async
//  closures on the cooperative thread pool regardless of any @MainActor
//  annotation on the surrounding struct or function — the actor isolation is
//  not forwarded through the macro-generated boilerplate.
//
//  The fix: make tests async and execute all store interaction inside
//  MainActor.run { }, which is the documented way to hop to the main actor
//  from a non-isolated async context. Container creation is also inside the
//  block because makeModelContainer is isolated to @MainActor.
//

import SwiftData
import Testing
@testable import Echo
import EchoCore

struct TranscriptionStoreTests {

    private func transcription(
        id: String,
        timestamp: Int64,
        text: String = "hello"
    ) -> Transcription {
        Transcription(
            id: id,
            text: text,
            timestamp: timestamp,
            model: "whisper-large-v3-turbo",
            audioPath: "/tmp/\(id).m4a",
            userId: "local"
        )
    }

    @Test("Store inserts and fetches newest transcriptions first")
    func insertAndFetchOrdering() async throws {
        try await MainActor.run {
            let container = try TranscriptionStore.makeModelContainer(inMemory: true)
            let store = TranscriptionStore(modelContext: container.mainContext)

            try store.insert(transcription(id: "older", timestamp: 100))
            try store.insert(transcription(id: "newer", timestamp: 200))

            let values = try store.fetch()
            #expect(values.map(\.id) == ["newer", "older"])
            #expect(try store.fetch(id: "older")?.userId == "local")
        }
    }

    @Test("Duplicate IDs are ignored like Room OnConflictStrategy.IGNORE")
    func duplicateInsertIsIgnored() async throws {
        try await MainActor.run {
            let container = try TranscriptionStore.makeModelContainer(inMemory: true)
            let store = TranscriptionStore(modelContext: container.mainContext)

            try store.insert(transcription(id: "same", timestamp: 100, text: "first"))
            try store.insert(transcription(id: "same", timestamp: 200, text: "second"))

            let values = try store.fetch()
            #expect(values.count == 1)
            #expect(values.first?.text == "first")
        }
    }

    @Test("Store updates and deletes existing records")
    func updateAndDelete() async throws {
        try await MainActor.run {
            let container = try TranscriptionStore.makeModelContainer(inMemory: true)
            let store = TranscriptionStore(modelContext: container.mainContext)

            try store.insert(transcription(id: "one", timestamp: 100))

            var changed = transcription(id: "one", timestamp: 300, text: "updated")
            changed.synced = true
            try store.update(changed)

            let updated = try store.fetch(id: "one")
            #expect(updated?.text == "updated")
            #expect(updated?.timestamp == 300)
            #expect(updated?.synced == true)

            try store.delete(id: "one")
            #expect(try store.fetch(id: "one") == nil)
        }
    }

    @Test("Fetch limit is honored and empty stores return no values")
    func fetchLimitAndEmptyStore() async throws {
        try await MainActor.run {
            let container = try TranscriptionStore.makeModelContainer(inMemory: true)
            let store = TranscriptionStore(modelContext: container.mainContext)

            #expect(try store.fetch().isEmpty)

            for index in 0..<4 {
                try store.insert(transcription(id: "id-\(index)", timestamp: Int64(index)))
            }

            #expect(try store.fetch(limit: 2).count == 2)
            #expect(try store.fetch(limit: 0).isEmpty)
        }
    }

    // MARK: - Phase 8 integration: duration field round-trip

    @Test("Duration is persisted and retrieved correctly")
    func durationRoundTrip() async throws {
        try await MainActor.run {
            let container = try TranscriptionStore.makeModelContainer(inMemory: true)
            let store = TranscriptionStore(modelContext: container.mainContext)

            let t = Transcription(
                id: "dur-test",
                text: "With duration",
                timestamp: 1_000,
                model: "whisper-large-v3-turbo",
                userId: "u",
                duration: 42.5
            )
            try store.insert(t)

            let fetched = try store.fetch(id: "dur-test")
            #expect(fetched?.duration == 42.5)
        }
    }

    @Test("Nil duration is stored as absent and round-trips as nil")
    func durationNilRoundTrip() async throws {
        try await MainActor.run {
            let container = try TranscriptionStore.makeModelContainer(inMemory: true)
            let store = TranscriptionStore(modelContext: container.mainContext)

            let t = Transcription(
                id: "dur-nil",
                text: "No duration",
                timestamp: 2_000,
                model: "m",
                userId: "u",
                duration: nil
            )
            try store.insert(t)

            let fetched = try store.fetch(id: "dur-nil")
            #expect(fetched?.duration == nil)
        }
    }

    @Test("Duration is updated correctly via store.update")
    func durationUpdate() async throws {
        try await MainActor.run {
            let container = try TranscriptionStore.makeModelContainer(inMemory: true)
            let store = TranscriptionStore(modelContext: container.mainContext)

            var t = Transcription(
                id: "dur-upd",
                text: "Original",
                timestamp: 3_000,
                model: "m",
                userId: "u",
                duration: 10.0
            )
            try store.insert(t)

            t.duration = 25.0
            try store.update(t)

            let updated = try store.fetch(id: "dur-upd")
            #expect(updated?.duration == 25.0)
        }
    }
}
