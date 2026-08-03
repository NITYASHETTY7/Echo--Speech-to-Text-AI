//
//  AudioFileManagerTests.swift
//  EchoTests
//

import Foundation
import Testing
@testable import EchoCore

// MARK: - In-memory FileSystem mock

final class MockFileSystem: FileSysteming {
    var existingPaths: Set<String> = []
    var directories: [String] = []
    var removed: [URL] = []
    var fileAttributes: [String: [FileAttributeKey: Any]] = [:]

    func fileExists(atPath path: String) -> Bool {
        existingPaths.contains(path)
    }

    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        directories.append(url.path)
        existingPaths.insert(url.path)
    }

    func removeItem(at url: URL) throws {
        existingPaths.remove(url.path)
        removed.append(url)
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        fileAttributes.keys
            .filter { $0.hasPrefix(url.path) }
            .map { URL(filePath: $0) }
    }

    func attributesOfItem(at url: URL) throws -> [FileAttributeKey: Any] {
        fileAttributes[url.path] ?? [:]
    }
}

// MARK: - Tests

struct AudioFileManagerTests {

    @Test("prepareDirectory creates the recordings directory")
    func prepareDirectoryCreatesDirectory() throws {
        let fs = MockFileSystem()
        let config = RecordingConfiguration.standard
        let manager = AudioFileManager(configuration: config, fileSystem: fs, clock: { .now })
        try manager.prepareDirectory()
        #expect(fs.directories.contains(config.recordingsDirectory.path))
    }

    @Test("prepareDirectory is idempotent if directory already exists")
    func prepareDirectoryIsIdempotent() throws {
        let fs = MockFileSystem()
        let config = RecordingConfiguration.standard
        fs.existingPaths.insert(config.recordingsDirectory.path)
        let manager = AudioFileManager(configuration: config, fileSystem: fs, clock: { .now })
        try manager.prepareDirectory()
        #expect(fs.directories.isEmpty)  // should NOT call createDirectory again
    }

    @Test("newRecordingURL returns a URL inside the recordings directory")
    func newRecordingURLIsInsideDirectory() throws {
        let fs = MockFileSystem()
        let config = RecordingConfiguration.standard
        let manager = AudioFileManager(configuration: config, fileSystem: fs)
        let url = try manager.newRecordingURL()
        #expect(url.deletingLastPathComponent() == config.recordingsDirectory)
        #expect(url.pathExtension == "m4a")
    }

    @Test("newRecordingURL avoids collisions by retrying with a later clock value")
    func newRecordingURLAvoidsCollisions() throws {
        let fs = MockFileSystem()
        let config = RecordingConfiguration.standard
        var callCount = 0
        let dates: [Date] = [
            Date(timeIntervalSince1970: 1000),
            Date(timeIntervalSince1970: 1000), // duplicate
            Date(timeIntervalSince1970: 2000), // unique
        ]
        let manager = AudioFileManager(
            configuration: config,
            fileSystem: fs,
            clock: {
                let d = dates[callCount]
                callCount += 1
                return d
            }
        )

        // Pre-seed the first timestamp as "already existing".
        let firstURL = config.newFileURL(at: dates[0])
        fs.existingPaths.insert(firstURL.path)

        // newRecordingURL should skip the colliding timestamp and use the third.
        let url = try manager.newRecordingURL()
        #expect(url == config.newFileURL(at: dates[2]))
    }

    @Test("delete removes the file from the filesystem")
    func deleteRemovesFile() {
        let fs = MockFileSystem()
        let config = RecordingConfiguration.standard
        let fileURL = config.newFileURL()
        fs.existingPaths.insert(fileURL.path)
        let manager = AudioFileManager(configuration: config, fileSystem: fs)
        manager.delete(fileURL: fileURL)
        #expect(fs.removed.contains(fileURL))
        #expect(!fs.existingPaths.contains(fileURL.path))
    }

    @Test("cleanupOldRecordings removes files older than retention period")
    func cleanupRemovesOldFiles() {
        let fs = MockFileSystem()
        let config = RecordingConfiguration.standard

        let old = config.recordingsDirectory.appending(path: "recording_100.m4a")
        let fresh = config.recordingsDirectory.appending(path: "recording_200.m4a")
        let notAudio = config.recordingsDirectory.appending(path: "readme.txt")

        fs.existingPaths.insert(old.path)
        fs.existingPaths.insert(fresh.path)
        fs.existingPaths.insert(notAudio.path)

        // Old file: 60 days ago. Fresh file: 1 day ago.
        let oldDate = Date().addingTimeInterval(-60 * 86_400)
        let freshDate = Date().addingTimeInterval(-86_400)
        fs.fileAttributes[old.path] = [.modificationDate: oldDate, .size: Int64(1000)]
        fs.fileAttributes[fresh.path] = [.modificationDate: freshDate, .size: Int64(1000)]
        fs.fileAttributes[notAudio.path] = [.modificationDate: oldDate]

        let manager = AudioFileManager(configuration: config, fileSystem: fs)
        manager.cleanupOldRecordings(olderThan: 30)

        #expect(fs.removed.contains(old))
        #expect(!fs.removed.contains(fresh))
        #expect(!fs.removed.contains(notAudio)) // non-audio file untouched
    }

    @Test("fileSize returns the file size from filesystem attributes")
    func fileSizeReturnsCorrectBytes() {
        let fs = MockFileSystem()
        let config = RecordingConfiguration.standard
        let fileURL = config.newFileURL()
        fs.fileAttributes[fileURL.path] = [.size: Int64(48_000)]
        let manager = AudioFileManager(configuration: config, fileSystem: fs)
        #expect(manager.fileSize(at: fileURL) == 48_000)
    }

    @Test("fileSize returns 0 when file attributes are unavailable")
    func fileSizeReturnsZeroWhenMissing() {
        let fs = MockFileSystem()
        let config = RecordingConfiguration.standard
        let fileURL = config.newFileURL()
        let manager = AudioFileManager(configuration: config, fileSystem: fs)
        #expect(manager.fileSize(at: fileURL) == 0)
    }
}
