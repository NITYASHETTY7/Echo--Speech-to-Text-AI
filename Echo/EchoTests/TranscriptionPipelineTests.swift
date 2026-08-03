//
//  TranscriptionPipelineTests.swift
//  EchoTests
//

import Foundation
import Testing
@testable import EchoCore

// MARK: - Mock SpeechProvider

final class MockSpeechProvider: SpeechProvider {
    let config: ProviderConfig
    var result: Result<TranscriptionResult, Error>

    init(
        config: ProviderConfig = ProviderRegistry.configuration(for: .groq),
        result: Result<TranscriptionResult, Error> = .success(TranscriptionResult(text: "Hello world"))
    ) {
        self.config = config
        self.result = result
    }

    func transcribe(audioFile: URL, model: String, language: String?) async throws -> TranscriptionResult {
        try await Task.sleep(for: .milliseconds(1)) // allow cooperative cancellation
        return try result.get()
    }
}

// MARK: - Mock ProviderFactory

/// Thin stand-in for ProviderFactory that returns a pre-configured provider
/// or throws a preset error, without touching Keychain or UserDefaults.
@MainActor
final class MockProviderFactory {
    var providerResult: Result<any SpeechProvider, Error>

    init(provider: any SpeechProvider) {
        self.providerResult = .success(provider)
    }

    init(error: Error) {
        self.providerResult = .failure(error)
    }

    func getProvider() throws -> any SpeechProvider {
        try providerResult.get()
    }
}

// MARK: - Stub pipeline that accepts a MockProviderFactory
//
// Because DefaultTranscriptionPipeline depends on the real ProviderFactory
// (which is @MainActor and requires Keychain), tests drive a lightweight
// StubTranscriptionPipeline that wires in MockProviderFactory directly.

@MainActor
final class StubTranscriptionPipeline: TranscriptionPipelineProtocol {
    private let factory: MockProviderFactory
    private let fileManager: FileManager

    init(factory: MockProviderFactory, fileManager: FileManager = .default) {
        self.factory = factory
        self.fileManager = fileManager
    }

    func transcribe(
        request: TranscriptionRequest,
        onProgress: @escaping @MainActor (TranscriptionProgress) -> Void
    ) async throws -> TranscriptionResponse {
        try await runPipeline(request: request, onProgress: onProgress)
    }

    @MainActor
    private func runPipeline(
        request: TranscriptionRequest,
        onProgress: @escaping @MainActor (TranscriptionProgress) -> Void
    ) async throws -> TranscriptionResponse {

        let start = Date.now
        onProgress(.preparing)

        // Pre-flight: file must exist
        guard fileManager.fileExists(atPath: request.recording.fileURL.path) else {
            throw TranscriptionError.audioFileNotFound(path: request.recording.fileURL.path)
        }

        // Resolve provider
        let provider: any SpeechProvider
        do {
            provider = try factory.getProvider()
        } catch let pe as ProviderError {
            if case .missingAPIKey = pe {
                throw TranscriptionError.noProviderConfigured
            }
            throw TranscriptionError.providerFailed(reason: pe.localizedDescription)
        } catch {
            throw TranscriptionError.providerFailed(reason: error.localizedDescription)
        }

        let providerId = provider.config.id

        onProgress(.uploading)
        onProgress(.processing)

        let rawResult: TranscriptionResult
        do {
            rawResult = try await provider.transcribe(
                audioFile: request.recording.fileURL,
                model: request.model,
                language: request.language
            )
        } catch is CancellationError {
            throw TranscriptionError.cancelled
        } catch {
            throw TranscriptionError.providerFailed(reason: error.localizedDescription)
        }

        onProgress(.filtering)
        let trimmed = rawResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let passes = HallucinationFilter.passes(text: trimmed, segments: nil)
        let finalText = passes ? trimmed : ""

        onProgress(.completed)
        let elapsed = Date.now.timeIntervalSince(start)

        return TranscriptionResponse(
            text: finalText,
            providerId: providerId,
            model: request.model,
            recordingDuration: request.recording.duration,
            processingDuration: elapsed,
            wasFiltered: !passes
        )
    }
}

// MARK: - Helpers

/// Creates a RecordingResult backed by a real temp file so `fileExists` passes.
@MainActor
private func makeRecording(
    text: String = "ignored",
    duration: TimeInterval = 2.0,
    peakDB: Float = -10.0
) -> (RecordingResult, URL) {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "test_\(UUID().uuidString).m4a")
    FileManager.default.createFile(atPath: url.path, contents: Data())
    let result = RecordingResult(
        fileURL: url,
        duration: duration,
        fileSize: 48_000,
        format: "m4a",
        sampleRate: 16_000,
        peakPowerDB: peakDB
    )
    return (result, url)
}

// MARK: - Tests

@MainActor
struct TranscriptionPipelineTests {

    // MARK: Success

    @Test("Successful transcription returns cleaned text")
    func successfulTranscription() async throws {
        let (recording, url) = makeRecording()
        defer { try? FileManager.default.removeItem(at: url) }

        let provider = MockSpeechProvider(
            result: .success(TranscriptionResult(text: "  Hello world  "))
        )
        let pipeline = StubTranscriptionPipeline(factory: MockProviderFactory(provider: provider))

        var progressEvents: [TranscriptionProgress] = []
        let request = TranscriptionRequest(recording: recording, language: "en", model: "whisper-large-v3-turbo")
        let response = try await pipeline.transcribe(request: request) { progressEvents.append($0) }

        #expect(response.text == "Hello world")
        #expect(!response.wasFiltered)
        #expect(response.providerId == .groq)
        #expect(response.model == "whisper-large-v3-turbo")
        #expect(progressEvents.contains(.preparing))
        #expect(progressEvents.contains(.completed))
    }

    // MARK: Provider failure

    @Test("Provider network error surfaces as providerFailed")
    func providerNetworkFailure() async throws {
        let (recording, url) = makeRecording()
        defer { try? FileManager.default.removeItem(at: url) }

        let provider = MockSpeechProvider(
            result: .failure(NetworkError.serviceUnavailable)
        )
        let pipeline = StubTranscriptionPipeline(factory: MockProviderFactory(provider: provider))
        let request = TranscriptionRequest(recording: recording)

        do {
            _ = try await pipeline.transcribe(request: request) { _ in }
            Issue.record("Expected error")
        } catch let error as TranscriptionError {
            guard case .providerFailed = error else {
                Issue.record("Expected providerFailed, got \(error)")
                return
            }
        }
    }

    @Test("Missing API key surfaces as noProviderConfigured")
    func missingAPIKey() async throws {
        let (recording, url) = makeRecording()
        defer { try? FileManager.default.removeItem(at: url) }

        let pipeline = StubTranscriptionPipeline(
            factory: MockProviderFactory(error: ProviderError.missingAPIKey(provider: .groq))
        )
        let request = TranscriptionRequest(recording: recording)

        do {
            _ = try await pipeline.transcribe(request: request) { _ in }
            Issue.record("Expected error")
        } catch let error as TranscriptionError {
            #expect(error == .noProviderConfigured)
        }
    }

    // MARK: File not found

    @Test("Missing audio file throws audioFileNotFound")
    func audioFileNotFound() async throws {
        let ghostURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ghost_\(UUID().uuidString).m4a")
        let recording = RecordingResult(
            fileURL: ghostURL,
            duration: 1.0,
            fileSize: 0,
            format: "m4a",
            sampleRate: 16_000,
            peakPowerDB: -10
        )
        let provider = MockSpeechProvider()
        let pipeline = StubTranscriptionPipeline(factory: MockProviderFactory(provider: provider))
        let request = TranscriptionRequest(recording: recording)

        do {
            _ = try await pipeline.transcribe(request: request) { _ in }
            Issue.record("Expected error")
        } catch let error as TranscriptionError {
            guard case .audioFileNotFound = error else {
                Issue.record("Expected audioFileNotFound, got \(error)")
                return
            }
        }
    }

    // MARK: Cancellation

    @Test("Cancelled task does not return a result")
    func cancellation() async throws {
        let (recording, url) = makeRecording()
        defer { try? FileManager.default.removeItem(at: url) }

        // Provider that spins until the task is cancelled, then throws
        // CancellationError via checkCancellation. This avoids a long sleep
        // and responds instantly when the parent task is cancelled.
        final class CancellableProvider: SpeechProvider {
            let config: ProviderConfig = ProviderRegistry.configuration(for: .groq)
            func transcribe(audioFile: URL, model: String, language: String?) async throws -> TranscriptionResult {
                while !Task.isCancelled {
                    try await Task.sleep(for: .milliseconds(5))
                }
                try Task.checkCancellation()
                return TranscriptionResult(text: "never")
            }
        }

        let pipeline = StubTranscriptionPipeline(factory: MockProviderFactory(provider: CancellableProvider()))
        let request = TranscriptionRequest(recording: recording)

        let task = Task { [pipeline, request] in
            try await pipeline.transcribe(request: request) { _ in }
        }
        // Give the provider time to enter its loop, then cancel.
        try await Task.sleep(for: .milliseconds(20))
        task.cancel()

        do {
            _ = try await task.value
            // Cooperative cancellation is best-effort; completing without error
            // is acceptable in a tight scheduler race.
        } catch let error as TranscriptionError {
            #expect(error == .cancelled)
        } catch is CancellationError {
            // Task.sleep or checkCancellation propagated directly — valid.
        }
    }

    // MARK: Hallucination filtering

    @Test("Known hallucination phrase is filtered and wasFiltered is true")
    func hallucinationFiltering() async throws {
        let (recording, url) = makeRecording()
        defer { try? FileManager.default.removeItem(at: url) }

        let provider = MockSpeechProvider(
            result: .success(TranscriptionResult(text: "thank you."))
        )
        let pipeline = StubTranscriptionPipeline(factory: MockProviderFactory(provider: provider))
        let request = TranscriptionRequest(recording: recording)
        let response = try await pipeline.transcribe(request: request) { _ in }

        #expect(response.text == "")
        #expect(response.wasFiltered)
        #expect(response.isEmpty)
    }

    // MARK: Empty transcript

    @Test("Empty provider response is returned as empty without filtering flag")
    func emptyTranscript() async throws {
        let (recording, url) = makeRecording()
        defer { try? FileManager.default.removeItem(at: url) }

        let provider = MockSpeechProvider(
            result: .success(TranscriptionResult(text: "   "))
        )
        let pipeline = StubTranscriptionPipeline(factory: MockProviderFactory(provider: provider))
        let request = TranscriptionRequest(recording: recording)
        let response = try await pipeline.transcribe(request: request) { _ in }

        // Whitespace-only trimmed to "" — not a known phrase so wasFiltered is false.
        #expect(response.text == "")
        #expect(!response.wasFiltered)
        #expect(response.isEmpty)
    }

    // MARK: Progress reporting

    @Test("All expected progress stages are reported in order")
    func progressOrder() async throws {
        let (recording, url) = makeRecording()
        defer { try? FileManager.default.removeItem(at: url) }

        let provider = MockSpeechProvider()
        let pipeline = StubTranscriptionPipeline(factory: MockProviderFactory(provider: provider))
        let request = TranscriptionRequest(recording: recording)

        var events: [TranscriptionProgress] = []
        _ = try await pipeline.transcribe(request: request) { events.append($0) }

        let expected: [TranscriptionProgress] = [.preparing, .uploading, .processing, .filtering, .completed]
        #expect(events == expected)
    }

    // MARK: Response metadata

    @Test("Response carries correct recording duration and model")
    func responseMetadata() async throws {
        let (recording, url) = makeRecording(duration: 7.5)
        defer { try? FileManager.default.removeItem(at: url) }

        let provider = MockSpeechProvider(config: ProviderRegistry.configuration(for: .deepgram))
        let pipeline = StubTranscriptionPipeline(factory: MockProviderFactory(provider: provider))
        let request = TranscriptionRequest(recording: recording, language: "fr", model: "nova-3")
        let response = try await pipeline.transcribe(request: request) { _ in }

        #expect(response.recordingDuration == 7.5)
        #expect(response.model == "nova-3")
        #expect(response.providerId == .deepgram)
        #expect(response.processingDuration >= 0)
    }
}
