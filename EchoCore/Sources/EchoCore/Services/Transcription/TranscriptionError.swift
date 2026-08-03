//
//  TranscriptionError.swift
//  Echo
//
//  Typed errors that the TranscriptionPipeline surface to callers.
//  All provider-level and network-level errors are wrapped in .providerFailed
//  so callers never need to import provider-specific error types.
//

import Foundation

public enum TranscriptionError: LocalizedError, Equatable, Sendable {

    // MARK: - Pre-flight

    /// No provider has been selected or configured.
    case noProviderConfigured

    /// The audio file referenced by the recording no longer exists.
    case audioFileNotFound(path: String)

    /// The recording is silent (peak power below the silence threshold).
    case silentRecording

    // MARK: - Pipeline

    /// The provider rejected the request or returned an error.
    /// The wrapped string is the localised description from the underlying error.
    case providerFailed(reason: String)

    /// The job was cancelled by the caller before the provider responded.
    case cancelled

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        case .noProviderConfigured:
            return "No speech provider is configured. Open Settings to add an API key."
        case .audioFileNotFound(let path):
            return "The audio file could not be found at \(path)."
        case .silentRecording:
            return "The recording appears to be silent and was not sent for transcription."
        case .providerFailed(let reason):
            return "Transcription failed: \(reason)"
        case .cancelled:
            return "Transcription was cancelled."
        }
    }

    // MARK: - Equatable (associated values compared by content)

    public static func == (lhs: TranscriptionError, rhs: TranscriptionError) -> Bool {
        switch (lhs, rhs) {
        case (.noProviderConfigured, .noProviderConfigured): return true
        case (.silentRecording, .silentRecording):           return true
        case (.cancelled, .cancelled):                       return true
        case (.audioFileNotFound(let l), .audioFileNotFound(let r)): return l == r
        case (.providerFailed(let l),    .providerFailed(let r)):    return l == r
        default: return false
        }
    }
}
