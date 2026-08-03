//
//  TranscriptionRequest.swift
//  Echo
//
//  Value type that bundles everything the pipeline needs to run one
//  transcription job.  Constructed from a RecordingResult plus the
//  caller-supplied preferences and is then passed down through the
//  pipeline without mutation.
//

import Foundation

/// All inputs required to execute a single transcription job.
struct TranscriptionRequest: Sendable {

    // MARK: - Audio source

    /// The completed recording produced by AudioRecorder.
    let recording: RecordingResult

    // MARK: - Provider settings (resolved by the caller from Preferences /
    // ProviderSettings before the request is created)

    /// BCP-47 language tag, e.g. "en". `nil` lets the provider auto-detect.
    let language: String?

    /// Model identifier forwarded verbatim to the provider.
    let model: String

    // MARK: - Init

    init(
        recording: RecordingResult,
        language: String? = AppConfig.Defaults.language,
        model: String = AppConfig.Defaults.model
    ) {
        self.recording = recording
        self.language = language
        self.model = model
    }
}
