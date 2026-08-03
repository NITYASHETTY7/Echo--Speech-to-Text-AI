//
//  AudioFileManager.swift
//  Echo
//
//  Manages audio recording file lifecycle: directory setup, filename
//  generation, and cleanup of stale temp files.
//
//  Android source of truth:
//    AudioFileManager.kt — timestamped filenames, recordings sub-directory.
//

import Foundation
import os

/// Protocol for testability — production code uses the default filesystem.
protocol FileSysteming: Sendable {
    func fileExists(atPath: String) -> Bool
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws
    func removeItem(at url: URL) throws
    func contentsOfDirectory(at url: URL) throws -> [URL]
    func attributesOfItem(at url: URL) throws -> [FileAttributeKey: Any]
}

struct DefaultFileSystem: FileSysteming {
    func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
    func createDirectory(at url: URL, withIntermediateDirectories create: Bool) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: create)
    }
    func removeItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
    func contentsOfDirectory(at url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: .skipsHiddenFiles
        )
    }
    func attributesOfItem(at url: URL) throws -> [FileAttributeKey: Any] {
        try FileManager.default.attributesOfItem(atPath: url.path)
    }
}

final class AudioFileManager {
    private let configuration: RecordingConfiguration
    private let fileSystem: FileSysteming
    private let clock: () -> Date

    init(
        configuration: RecordingConfiguration = .standard,
        fileSystem: FileSysteming = DefaultFileSystem(),
        clock: @escaping () -> Date = { .now }
    ) {
        self.configuration = configuration
        self.fileSystem = fileSystem
        self.clock = clock
    }

    // MARK: - Directory

    /// Ensures the recordings directory exists, creating it if needed.
    func prepareDirectory() throws {
        let dir = configuration.recordingsDirectory
        guard !fileSystem.fileExists(atPath: dir.path) else { return }
        do {
            try fileSystem.createDirectory(at: dir, withIntermediateDirectories: true)
            EchoLog.audio.debug("Created recordings directory: \(dir.path, privacy: .public)")
        } catch {
            EchoLog.audio.error("Failed to create directory: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    // MARK: - File generation

    /// Returns a new unique file URL. Matches Android's pattern:
    /// `recording_${System.currentTimeMillis()}.m4a`
    func newRecordingURL() throws -> URL {
        try prepareDirectory()
        var url = configuration.newFileURL(at: clock())

        // Guarantee uniqueness without ever spinning. The base filename is a
        // millisecond timestamp, so two calls within the same millisecond — or a
        // clock that does not advance — would otherwise regenerate the identical
        // path forever and hang the caller. Re-sample the clock a bounded number
        // of times (a normal running clock advances and yields a new name), then
        // fall back to a deterministic numeric suffix that is guaranteed to
        // terminate.
        let maxClockRetries = 8
        var attempt = 0
        while fileSystem.fileExists(atPath: url.path) {
            attempt += 1
            if attempt <= maxClockRetries {
                url = configuration.newFileURL(at: clock())
            } else {
                url = configuration.newFileURL(at: clock(), suffix: attempt)
            }
        }
        return url
    }

    // MARK: - Cleanup

    /// Deletes a specific recording file.
    func delete(fileURL: URL) {
        guard fileSystem.fileExists(atPath: fileURL.path) else { return }
        do {
            try fileSystem.removeItem(at: fileURL)
            EchoLog.audio.debug("Deleted recording: \(fileURL.lastPathComponent, privacy: .public)")
        } catch {
            EchoLog.audio.error("Failed to delete recording: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Deletes all recordings older than `olderThan` days.
    func cleanupOldRecordings(olderThan days: Int = 30) {
        guard let urls = try? fileSystem.contentsOfDirectory(at: configuration.recordingsDirectory) else {
            return
        }
        let cutoff = Date().addingTimeInterval(-TimeInterval(days) * 86_400)
        for url in urls where url.pathExtension.lowercased() == configuration.fileExtension {
            guard let attrs = try? fileSystem.attributesOfItem(at: url),
                  let modified = attrs[.modificationDate] as? Date,
                  modified < cutoff else { continue }
            do {
                try fileSystem.removeItem(at: url)
                EchoLog.audio.debug("Cleaned up old recording: \(url.lastPathComponent, privacy: .public)")
            } catch {
                EchoLog.audio.error("Cleanup failed for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Returns the size of a file in bytes, or 0 if unavailable.
    func fileSize(at url: URL) -> Int64 {
        guard let attrs = try? fileSystem.attributesOfItem(at: url),
              let size = attrs[.size] as? Int64 else { return 0 }
        return size
    }
}
