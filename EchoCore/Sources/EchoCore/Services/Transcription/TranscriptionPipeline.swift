//
//  TranscriptionPipeline.swift
//  Echo
//
//  Protocol + default implementation of the one-shot transcription pipeline.
//
//  Pipeline steps (mirrors the Android TranscriptionService flow):
//    1. Pre-flight: file exists, not silent.
//    2. Resolve provider via ProviderFactory.
//    3. Call provider.transcribe(audioFile:model:language:).
//    4. Apply HallucinationFilter.
//    5. Return TranscriptionResponse.
//
//  Progress is reported via an async stream of TranscriptionProgress values so
//  callers can update UI without coupling to pipeline internals.
//

import Foundation
import os

// MARK: - Progress

/// Discrete pipeline stages surfaced to the caller through the progress stream.
public enum TranscriptionProgress: Equatable, Sendable {
    case preparing
    case uploading
    case processing
    case filtering
    case completed
}

// MARK: - Protocol

/// Testability boundary for the pipeline. Inject this protocol wherever the
/// pipeline is consumed so tests can substitute MockTranscriptionPipeline.
public protocol TranscriptionPipelineProtocol: Sendable {
    /// Executes the full pipeline for `request`.
    /// - Throws: `TranscriptionError` for all failure modes.
    @MainActor
    func transcribe(
        request: TranscriptionRequest,
        onProgress: @escaping @MainActor (TranscriptionProgress) -> Void
    ) async throws -> TranscriptionResponse
}

// MARK: - Default implementation

/// Production pipeline. `@MainActor` because `ProviderFactory` is
/// `@MainActor`-isolated and we must call it without hopping.
@MainActor
public final class DefaultTranscriptionPipeline: TranscriptionPipelineProtocol {

    // MARK: - Dependencies

    private let providerFactory: ProviderFactory
    private let fileManager: FileManager
    private let clock: @Sendable () -> Date

    // MARK: - Init

    public init(
        providerFactory: ProviderFactory,
        fileManager: FileManager = .default,
        clock: @escaping @Sendable () -> Date = { .now }
    ) {
        self.providerFactory = providerFactory
        self.fileManager = fileManager
        self.clock = clock
    }

    // MARK: - TranscriptionPipelineProtocol

    public func transcribe(
        request: TranscriptionRequest,
        onProgress: @escaping @MainActor (TranscriptionProgress) -> Void
    ) async throws -> TranscriptionResponse {
        try await runPipeline(request: request, onProgress: onProgress)
    }

    // MARK: - Pipeline execution

    /// Runs all pipeline steps synchronously on the MainActor. The provider's
    /// `transcribe` call is async, so we cannot literally be "synchronous", but
    /// all steps begin and complete inside `@MainActor` context.
    @MainActor
    private func runPipeline(
        request: TranscriptionRequest,
        onProgress: @escaping @MainActor (TranscriptionProgress) -> Void
    ) async throws -> TranscriptionResponse {

        let start = clock()
        onProgress(.preparing)

        // ── Step 1: pre-flight ───────────────────────────────────────────────

        let audioURL = request.recording.fileURL
        guard fileManager.fileExists(atPath: audioURL.path) else {
            throw TranscriptionError.audioFileNotFound(path: audioURL.path)
        }

        if isSilent(recording: request.recording) {
            throw TranscriptionError.silentRecording
        }

        // ── Step 2: resolve provider ─────────────────────────────────────────

        let provider: any SpeechProvider
        do {
            provider = try providerFactory.getProvider()
        } catch let pe as ProviderError {
            if case .missingAPIKey = pe {
                throw TranscriptionError.noProviderConfigured
            }
            throw TranscriptionError.providerFailed(reason: pe.localizedDescription)
        } catch {
            throw TranscriptionError.providerFailed(reason: error.localizedDescription)
        }

        let providerId = provider.config.id

        // ── Step 3: upload & transcribe ──────────────────────────────────────

        onProgress(.uploading)
        let rawResult: TranscriptionResult
        do {
            onProgress(.processing)
            rawResult = try await provider.transcribe(
                audioFile: audioURL,
                model: request.model,
                language: request.language
            )
        } catch is CancellationError {
            throw TranscriptionError.cancelled
        } catch {
            throw TranscriptionError.providerFailed(reason: error.localizedDescription)
        }

        // ── Step 4: hallucination filter ─────────────────────────────────────

        onProgress(.filtering)
        let trimmed = rawResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let passes = HallucinationFilter.passes(text: trimmed, segments: nil)
        let finalText = passes ? trimmed : ""
        let wasFiltered = !passes

        // ── Step 5: build response ───────────────────────────────────────────

        let processingDuration = clock().timeIntervalSince(start)
        onProgress(.completed)

        // Detect spoken language from the final (non-filtered) text.
        // Uses on-device NLLanguageRecognizer — no network call.
        let detectedLanguage = LanguageDetector.detect(text: finalText)

        let elapsedStr = String(format: "%.2f", processingDuration)
        EchoLog.audio.debug(
            "Pipeline done: provider=\(providerId.rawValue, privacy: .public) filtered=\(wasFiltered, privacy: .public) chars=\(finalText.count, privacy: .public) lang=\(detectedLanguage, privacy: .public) elapsed=\(elapsedStr, privacy: .public)s"
        )

        return TranscriptionResponse(
            text: finalText,
            providerId: providerId,
            model: request.model,
            recordingDuration: request.recording.duration,
            processingDuration: processingDuration,
            wasFiltered: wasFiltered,
            detectedLanguage: detectedLanguage
        )
    }

    // MARK: - Helpers

    /// Mirrors Android's PillController silence check (linear peak amplitude).
    /// `RecordingResult.peakPowerDB` is in dBFS; convert to a 0–1 linear scale
    /// and compare against the Android linear threshold normalised to 0–1.
    private func isSilent(recording: RecordingResult) -> Bool {
        guard let peakDB = recording.peakPowerDB else { return false }
        // dBFS → linear (0…1): linear = 10^(dBFS/20)
        let linear = pow(10.0, Double(peakDB) / 20.0)
        // Android threshold is 1500 out of 32767 ≈ 0.0458
        let threshold = Double(AppConfig.Silence.androidLinearThreshold)
                      / Double(AppConfig.Silence.androidLinearMax)
        return linear < threshold
    }
}
