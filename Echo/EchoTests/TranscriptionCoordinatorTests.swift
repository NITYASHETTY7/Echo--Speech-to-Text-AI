//
//  TranscriptionCoordinatorTests.swift
//  EchoTests
//

import Foundation
import Testing
@testable import EchoCore

// MARK: - Stub pipeline for coordinator tests

/// Synchronous-ish stub: resolves immediately with a preset result.
@MainActor
final class StubPipeline: TranscriptionPipelineProtocol {
    private var _result: Result<TranscriptionResponse, TranscriptionError>

    @MainActor
    init(response: TranscriptionResponse) {
        _result = .success(response)
    }

    @MainActor
    init(error: TranscriptionError) {
        _result = .failure(error)
    }

    func transcribe(
        request: TranscriptionRequest,
        onProgress: @escaping @MainActor (TranscriptionProgress) -> Void
    ) async throws -> TranscriptionResponse {
        onProgress(.preparing)
        onProgress(.processing)
        onProgress(.completed)
        switch _result {
        case .success(let r): return r
        case .failure(let e): throw e
        }
    }
}

// MARK: - Convenience factory for StubPipeline

extension StubPipeline {
    @MainActor
    static func success(text: String = "Hello world") -> StubPipeline {
        StubPipeline(response: TranscriptionResponse(
            text: text,
            providerId: .groq,
            model: "whisper-large-v3-turbo",
            recordingDuration: 2.0,
            processingDuration: 0.1
        ))
    }

    @MainActor
    static func failure(_ error: TranscriptionError) -> StubPipeline {
        StubPipeline(error: error)
    }
}

// MARK: - Test helpers

@MainActor
private func makeCoordinator(
    pipeline: any TranscriptionPipelineProtocol
) -> (TranscriptionCoordinator, Preferences, ProviderSettings) {
    let prefs = Preferences(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
    let provSettings = ProviderSettings(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
    let coordinator = TranscriptionCoordinator(
        pipeline: pipeline,
        preferences: prefs,
        providerSettings: provSettings,
        store: nil
    )
    return (coordinator, prefs, provSettings)
}

@MainActor
private func makeRecordingResult(peakDB: Float = -10) -> RecordingResult {
    RecordingResult(
        fileURL: URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "coord_\(UUID().uuidString).m4a"),
        duration: 2.0,
        fileSize: 48_000,
        format: "m4a",
        sampleRate: 16_000,
        peakPowerDB: peakDB
    )
}

// MARK: - Tests

@MainActor
struct TranscriptionCoordinatorTests {

    // MARK: Successful transcription

    @Test("Successful transcription transitions state to completed")
    func successTransitionsToCompleted() async throws {
        let pipeline = StubPipeline.success(text: "Meeting notes")
        let (coordinator, _, _) = makeCoordinator(pipeline: pipeline)

        var states: [CoordinatorState] = []
        coordinator.onStateChange = { states.append($0) }

        coordinator.transcribe(recording: makeRecordingResult())
        // Yield to the run loop so the coordinator's unstructured Task can execute.
        for _ in 0..<20 { await Task.yield() }

        if case .completed(let response) = coordinator.state {
            #expect(response.text == "Meeting notes")
        } else {
            Issue.record("Expected .completed, got \(coordinator.state)")
        }
        #expect(states.contains(where: { if case .transcribing = $0 { return true }; return false }))
    }

    // MARK: Provider failure

    @Test("Provider failure transitions state to failed")
    func providerFailureTransitionsToFailed() async throws {
        let pipeline = StubPipeline.failure(.providerFailed(reason: "503"))
        let (coordinator, _, _) = makeCoordinator(pipeline: pipeline)

        coordinator.transcribe(recording: makeRecordingResult())
        for _ in 0..<20 { await Task.yield() }

        guard case .failed(let error) = coordinator.state else {
            Issue.record("Expected .failed, got \(coordinator.state)")
            return
        }
        #expect(error == .providerFailed(reason: "503"))
    }

    // MARK: No provider configured

    @Test("noProviderConfigured error transitions state to failed")
    func noProviderConfigured() async throws {
        let pipeline = StubPipeline.failure(.noProviderConfigured)
        let (coordinator, _, _) = makeCoordinator(pipeline: pipeline)

        coordinator.transcribe(recording: makeRecordingResult())
        for _ in 0..<20 { await Task.yield() }

        #expect(coordinator.state == .failed(.noProviderConfigured))
    }

    // MARK: Cancellation

    @Test("cancel() stops transcription and transitions to cancelled")
    func cancelTranscription() async throws {
        // Use a pipeline that pauses long enough to be cancelled.
        final class PausedPipeline: TranscriptionPipelineProtocol {
            func transcribe(
                request: TranscriptionRequest,
                onProgress: @escaping @MainActor (TranscriptionProgress) -> Void
            ) async throws -> TranscriptionResponse {
                try await Task.sleep(for: .seconds(60))
                throw TranscriptionError.cancelled
            }
        }

        let (coordinator, _, _) = makeCoordinator(pipeline: PausedPipeline())
        coordinator.transcribe(recording: makeRecordingResult())
        coordinator.cancel()

        #expect(coordinator.state == .cancelled)
    }

    @Test("Second transcribe call cancels the first and starts fresh")
    func secondCallCancelsFirst() async throws {
        let pipeline = StubPipeline.success(text: "Second result")
        let (coordinator, _, _) = makeCoordinator(pipeline: pipeline)

        coordinator.transcribe(recording: makeRecordingResult())
        coordinator.transcribe(recording: makeRecordingResult())

        for _ in 0..<20 { await Task.yield() }

        if case .completed(let r) = coordinator.state {
            #expect(r.text == "Second result")
        } else {
            Issue.record("Expected .completed, got \(coordinator.state)")
        }
    }

    // MARK: onStateChange callback

    @Test("onStateChange fires for every state transition")
    func onStateChangeCallback() async throws {
        let pipeline = StubPipeline.success()
        let (coordinator, _, _) = makeCoordinator(pipeline: pipeline)

        var changeCount = 0
        coordinator.onStateChange = { _ in changeCount += 1 }

        coordinator.transcribe(recording: makeRecordingResult())
        for _ in 0..<20 { await Task.yield() }

        // Expect at least one .transcribing + one .completed = 2+
        #expect(changeCount >= 2)
    }

    // MARK: Initial state

    @Test("Coordinator initial state is idle")
    func initialStateIsIdle() {
        let (coordinator, _, _) = makeCoordinator(pipeline: StubPipeline.success())
        #expect(coordinator.state == .idle)
    }

    // MARK: Language + model forwarding

    @Test("Coordinator forwards language and model from preferences to request")
    func languageAndModelForwarding() async throws {
        var capturedRequest: TranscriptionRequest?

        final class CapturingPipeline: TranscriptionPipelineProtocol {
            var capture: TranscriptionRequest?
            func transcribe(
                request: TranscriptionRequest,
                onProgress: @escaping @MainActor (TranscriptionProgress) -> Void
            ) async throws -> TranscriptionResponse {
                await MainActor.run { self.capture = request }
                return TranscriptionResponse(
                    text: "ok",
                    providerId: .groq,
                    model: request.model,
                    recordingDuration: 1,
                    processingDuration: 0
                )
            }
        }

        let capturingPipeline = CapturingPipeline()
        let prefs = Preferences(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        let provSettings = ProviderSettings(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.language = "fr"
        provSettings.selectedModel = "nova-3"

        let coordinator = TranscriptionCoordinator(
            pipeline: capturingPipeline,
            preferences: prefs,
            providerSettings: provSettings,
            store: nil
        )
        coordinator.transcribe(recording: makeRecordingResult())
        for _ in 0..<20 { await Task.yield() }

        capturedRequest = capturingPipeline.capture
        #expect(capturedRequest?.language == "fr")
        #expect(capturedRequest?.model == "nova-3")
    }
}
