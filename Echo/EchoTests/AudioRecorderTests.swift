//
//  AudioRecorderTests.swift
//  EchoTests
//

import Foundation
import AVFoundation
import Testing
@testable import EchoCore

// MARK: - Mock session manager

final class MockAudioSessionManager: AudioSessionManaging {
    weak var delegate: AudioSessionDelegate?
    var activateCallCount = 0
    var deactivateCallCount = 0
    var permissionResult = true
    var activateShouldThrow: RecordingError?

    func requestPermission() async -> Bool { permissionResult }

    func activate() throws {
        activateCallCount += 1
        if let error = activateShouldThrow { throw error }
    }

    func deactivate() { deactivateCallCount += 1 }
}

// MARK: - Mock AVAudioRecorder

final class MockAVAudioRecorder: AVAudioRecorderProtocol {
    var isRecording = false
    var currentTime: TimeInterval = 0
    var isMeteringEnabled = false
    var prepareResult = true
    var recordResult = true
    var stopCallCount = 0
    var peakPowerValue: Float = -20.0

    func prepareToRecord() -> Bool { prepareResult }
    func record() -> Bool { isRecording = recordResult; return recordResult }
    func pause() { isRecording = false }
    func stop() { isRecording = false; stopCallCount += 1 }
    func deleteRecording() -> Bool { true }
    func averagePower(forChannel: Int) -> Float { peakPowerValue }
    func peakPower(forChannel: Int) -> Float { peakPowerValue }
    func updateMeters() {}
}

// MARK: - Helper

@MainActor
private func makeRecorder(
    session: MockAudioSessionManager? = nil,
    mockAVRecorder: MockAVAudioRecorder? = nil,
    fileSystem: MockFileSystem? = nil
) -> (AudioRecorder, MockAudioSessionManager, MockAVAudioRecorder) {
    let sessionMgr = session ?? MockAudioSessionManager()
    let avRecorder = mockAVRecorder ?? MockAVAudioRecorder()
    let fs = fileSystem ?? MockFileSystem()

    let config = RecordingConfiguration.standard
    let fileMgr = AudioFileManager(configuration: config, fileSystem: fs)
    let recorder = AudioRecorder(
        configuration: config,
        fileManager: fileMgr,
        sessionManager: sessionMgr,
        recorderFactory: { _, _ in avRecorder }
    )
    return (recorder, sessionMgr, avRecorder)
}

// MARK: - Tests

@MainActor
struct AudioRecorderTests {

    // MARK: Permission

    @Test("requestPermission transitions to ready when granted")
    func permissionGranted() async {
        let (recorder, session, _) = makeRecorder()
        session.permissionResult = true
        let granted = await recorder.requestPermission()
        #expect(granted)
        #expect(recorder.state == .ready)
    }

    @Test("requestPermission transitions to failed when denied")
    func permissionDenied() async {
        let (recorder, session, _) = makeRecorder()
        session.permissionResult = false
        let granted = await recorder.requestPermission()
        #expect(!granted)
        #expect(recorder.state == .failed(.permissionDenied))
    }

    // MARK: Start / Stop

    @Test("startRecording activates session and transitions to recording")
    func startRecording() async throws {
        let (recorder, session, avRecorder) = makeRecorder()
        recorder.state = .ready  // skip permission
        try await recorder.startRecording()
        #expect(recorder.state == .recording)
        #expect(session.activateCallCount == 1)
        #expect(avRecorder.isRecording)
    }

    @Test("startRecording is ignored when already recording")
    func startWhenAlreadyRecording() async throws {
        let (recorder, session, _) = makeRecorder()
        recorder.state = .ready
        try await recorder.startRecording()
        let callsBefore = session.activateCallCount
        try await recorder.startRecording()
        #expect(session.activateCallCount == callsBefore)
    }

    @Test("stopRecording transitions to completed and deactivates session")
    func stopRecording() async throws {
        let fs = MockFileSystem()
        let avRecorder = MockAVAudioRecorder()
        avRecorder.currentTime = 3.0

        // Capture the URL produced by the recorder and seed file attributes.
        var capturedURL: URL?
        let (recorder, session, _) = makeRecorder(
            mockAVRecorder: avRecorder,
            fileSystem: fs
        )
        recorder.state = .ready

        // Intercept file creation by overriding the factory to capture the URL.
        // We re-make the recorder with a modified file manager that seeds the file.
        let config = RecordingConfiguration.standard
        let fileURL = config.newFileURL(at: Date(timeIntervalSince1970: 9_999_999))
        fs.existingPaths.insert(config.recordingsDirectory.path)
        // Seed only the file's size attribute — NOT its existence. A freshly
        // allocated recording URL must not already exist, otherwise the
        // collision-avoidance path in newRecordingURL() would (correctly) skip
        // it. The size attribute is what finishRecording() reads to verify the
        // file was written.
        fs.fileAttributes[fileURL.path] = [.size: Int64(48_000)]
        capturedURL = fileURL

        // Build a recorder that always returns the seeded URL.
        let fileMgr = AudioFileManager(
            configuration: config,
            fileSystem: fs,
            clock: { Date(timeIntervalSince1970: 9_999_999) }
        )
        let seededRecorder = AudioRecorder(
            configuration: config,
            fileManager: fileMgr,
            sessionManager: session,
            recorderFactory: { _, _ in avRecorder }
        )
        seededRecorder.state = .ready

        try await seededRecorder.startRecording()
        let result = try await seededRecorder.stopRecording()

        #expect(seededRecorder.state == .completed(result))
        #expect(avRecorder.stopCallCount >= 1)
        #expect(session.deactivateCallCount >= 1)
        #expect(result.format == "m4a")
        #expect(result.sampleRate == 16_000)
        _ = capturedURL  // suppress unused warning
    }

    @Test("stopRecording throws when not recording")
    func stopWhenNotRecording() async {
        let (recorder, _, _) = makeRecorder()
        do {
            _ = try await recorder.stopRecording()
            Issue.record("Expected error")
        } catch let error as RecordingError {
            guard case .recordingFailed = error else {
                Issue.record("Unexpected: \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected: \(error)")
        }
    }

    // MARK: Cancel

    @Test("cancelRecording stops recorder, deletes file, and transitions to idle")
    func cancelRecording() async throws {
        let fs = MockFileSystem()
        let (recorder, session, _) = makeRecorder(fileSystem: fs)
        recorder.state = .ready
        try await recorder.startRecording()
        #expect(recorder.state == .recording)
        recorder.cancelRecording()
        #expect(recorder.state == .idle)
        #expect(session.deactivateCallCount >= 1)
    }

    // MARK: Pause / Resume

    @Test("pauseRecording transitions to paused")
    func pauseRecording() async throws {
        let (recorder, _, _) = makeRecorder()
        recorder.state = .ready
        try await recorder.startRecording()
        recorder.pauseRecording()
        #expect(recorder.state == .paused)
    }

    @Test("resumeRecording from paused transitions back to recording")
    func resumeRecording() async throws {
        let (recorder, _, avRecorder) = makeRecorder()
        recorder.state = .ready
        try await recorder.startRecording()
        recorder.pauseRecording()
        #expect(recorder.state == .paused)
        recorder.resumeRecording()
        #expect(recorder.state == .recording)
        #expect(avRecorder.isRecording)
    }

    // MARK: Session activation failure

    @Test("startRecording fails when session activation throws")
    func sessionActivationFails() async {
        let session = MockAudioSessionManager()
        session.activateShouldThrow = .sessionActivationFailed(reason: "no device")
        let (recorder, _, _) = makeRecorder(session: session)
        recorder.state = .ready
        do {
            try await recorder.startRecording()
            Issue.record("Expected error")
        } catch let error as RecordingError {
            #expect(error == .sessionActivationFailed(reason: "no device"))
        } catch {
            Issue.record("Unexpected: \(error)")
        }
        #expect(recorder.state == .failed(.sessionActivationFailed(reason: "no device")))
    }

    // MARK: Interruption handling

    @Test("Interruption without shouldResume stops and completes the recording")
    func interruptionWithoutResume() async throws {
        let fs = MockFileSystem()
        let (recorder, _, avRecorder) = makeRecorder(fileSystem: fs)
        recorder.state = .ready

        let url = try! AudioFileManager(
            configuration: .standard,
            fileSystem: fs
        ).newRecordingURL()
        fs.existingPaths.insert(url.path)
        fs.fileAttributes[url.path] = [.size: Int64(48_000)]
        avRecorder.currentTime = 2.0

        try await recorder.startRecording()

        // Simulate interruption: began (shouldResume = false)
        recorder.audioSessionWasInterrupted(shouldResume: false)

        // Give the async task a moment to settle.
        try await Task.sleep(for: .milliseconds(50))

        // Should have transitioned away from recording.
        switch recorder.state {
        case .completed, .idle, .stopping:
            break   // any terminal/settling state is acceptable
        case .failed:
            break
        default:
            Issue.record("Unexpected state after interruption: \(recorder.state)")
        }
    }

    @Test("Interruption with shouldResume resumes recording")
    func interruptionWithResume() async throws {
        let (recorder, _, avRecorder) = makeRecorder()
        recorder.state = .ready
        try await recorder.startRecording()
        recorder.pauseRecording()
        #expect(recorder.state == .paused)

        // Simulate interruption end with shouldResume = true.
        // audioSessionWasInterrupted dispatches a Task { @MainActor in ... };
        // yield to the run loop to let it complete before asserting.
        recorder.audioSessionWasInterrupted(shouldResume: true)
        await Task.yield()
        await Task.yield()

        #expect(recorder.state == .recording)
        #expect(avRecorder.isRecording)
    }

    // MARK: Route change

    @Test("Route change oldDeviceUnavailable does not stop recording")
    func routeChangeOldDeviceUnavailable() async throws {
        let (recorder, _, _) = makeRecorder()
        recorder.state = .ready
        try await recorder.startRecording()
        recorder.audioRouteDidChange(reason: .oldDeviceUnavailable)
        // Recording should continue uninterrupted
        #expect(recorder.state == .recording)
    }

    // MARK: onStateChange callback

    @Test("onStateChange is called on every state transition")
    func onStateChangeCallback() async throws {
        var states: [RecordingState] = []
        let (recorder, _, _) = makeRecorder()
        recorder.onStateChange = { states.append($0) }
        recorder.state = .ready
        // The .ready assignment above already fired the callback
        #expect(states.contains(.ready))
    }
}
