//
//  RecordingStateTests.swift
//  EchoTests
//

import Foundation
import Testing
@testable import EchoCore

struct RecordingStateTests {

    @Test("isActive is true only for recording and paused")
    func isActive() {
        #expect(RecordingState.recording.isActive)
        #expect(RecordingState.paused.isActive)
        #expect(!RecordingState.idle.isActive)
        #expect(!RecordingState.ready.isActive)
        #expect(!RecordingState.stopping.isActive)
        let result = makeResult()
        #expect(!RecordingState.completed(result).isActive)
        #expect(!RecordingState.failed(.permissionDenied).isActive)
    }

    @Test("canStart is true for ready, completed, and failed")
    func canStart() {
        #expect(!RecordingState.idle.canStart)
        #expect(!RecordingState.requestingPermission.canStart)
        #expect(RecordingState.ready.canStart)
        #expect(!RecordingState.recording.canStart)
        #expect(!RecordingState.paused.canStart)
        #expect(!RecordingState.stopping.canStart)
        #expect(RecordingState.completed(makeResult()).canStart)
        #expect(RecordingState.failed(.permissionDenied).canStart)
    }

    @Test("canStop is true only for recording and paused")
    func canStop() {
        #expect(RecordingState.recording.canStop)
        #expect(RecordingState.paused.canStop)
        #expect(!RecordingState.idle.canStop)
        #expect(!RecordingState.ready.canStop)
        #expect(!RecordingState.stopping.canStop)
    }

    @Test("canPause is true only for recording")
    func canPause() {
        #expect(RecordingState.recording.canPause)
        #expect(!RecordingState.paused.canPause)
        #expect(!RecordingState.idle.canPause)
    }

    @Test("canResume is true only for paused")
    func canResume() {
        #expect(RecordingState.paused.canResume)
        #expect(!RecordingState.recording.canResume)
        #expect(!RecordingState.idle.canResume)
    }

    @Test("Equality: same-tag states are equal")
    func equality() {
        let r = makeResult()
        #expect(RecordingState.idle == .idle)
        #expect(RecordingState.recording == .recording)
        #expect(RecordingState.paused == .paused)
        #expect(RecordingState.completed(r) == .completed(r))
        #expect(RecordingState.failed(.permissionDenied) == .failed(.permissionDenied))
        #expect(RecordingState.idle != .recording)
    }

    private func makeResult() -> RecordingResult {
        RecordingResult(
            fileURL: URL(filePath: "/tmp/test.m4a"),
            duration: 3.0,
            fileSize: 48000,
            format: "m4a",
            sampleRate: 16_000,
            peakPowerDB: -12.0
        )
    }
}
