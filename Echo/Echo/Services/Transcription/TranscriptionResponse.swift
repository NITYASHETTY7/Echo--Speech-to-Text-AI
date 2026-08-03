//
//  TranscriptionResponse.swift
//  Echo
//
//  The cleaned, provider-agnostic result returned by the pipeline.
//  This is distinct from TranscriptionResult (the raw provider contract) so
//  that pipeline-level metadata (provenance, timing, filtering) can be added
//  without touching the SpeechProvider protocol.
//

import Foundation

/// The pipeline's output after provider transcription and hallucination
/// filtering have both been applied.
struct TranscriptionResponse: Equatable, Sendable {

    // MARK: - Core payload

    /// Final, cleaned transcript text.  Empty string means silence was detected
    /// or the hallucination filter discarded the raw output.
    let text: String

    // MARK: - Provenance

    /// The provider that produced this transcript.
    let providerId: ProviderId

    /// The model used by the provider.
    let model: String

    /// Duration of the source recording in seconds.
    let recordingDuration: TimeInterval

    /// Wall-clock time from pipeline entry to response available, in seconds.
    let processingDuration: TimeInterval

    // MARK: - Filter metadata

    /// `true` when the hallucination filter discarded the raw provider output.
    let wasFiltered: Bool

    // MARK: - Init

    init(
        text: String,
        providerId: ProviderId,
        model: String,
        recordingDuration: TimeInterval,
        processingDuration: TimeInterval,
        wasFiltered: Bool = false
    ) {
        self.text = text
        self.providerId = providerId
        self.model = model
        self.recordingDuration = recordingDuration
        self.processingDuration = processingDuration
        self.wasFiltered = wasFiltered
    }

    /// Convenience: whether the response contains usable transcribed speech.
    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
