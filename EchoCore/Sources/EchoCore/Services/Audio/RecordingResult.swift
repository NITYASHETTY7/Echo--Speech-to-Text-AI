//
//  RecordingResult.swift
//  Echo
//
//  Value type returned when recording completes successfully.
//

import Foundation

public struct RecordingResult: Equatable, Sendable {
    /// URL of the finished audio file.
    public let fileURL: URL
    /// Total recorded duration in seconds.
    public let duration: TimeInterval
    /// Size of the file in bytes.
    public let fileSize: Int64
    /// Audio format identifier (e.g. "com.apple.m4a-audio").
    public let format: String
    /// Sample rate in Hz used for the recording.
    public let sampleRate: Double
    /// Peak amplitude in dB measured across the session, or nil if metering
    /// was unavailable.
    public let peakPowerDB: Float?

    public init(
        fileURL: URL,
        duration: TimeInterval,
        fileSize: Int64,
        format: String,
        sampleRate: Double,
        peakPowerDB: Float?
    ) {
        self.fileURL = fileURL
        self.duration = duration
        self.fileSize = fileSize
        self.format = format
        self.sampleRate = sampleRate
        self.peakPowerDB = peakPowerDB
    }
}

public enum RecordingError: Error, LocalizedError, Equatable, Sendable {
    case permissionDenied
    case sessionActivationFailed(reason: String)
    case recorderSetupFailed(reason: String)
    case recordingFailed(reason: String)
    case fileEmpty
    case interrupted

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone access was denied. Go to Settings → Privacy → Microphone to allow Echo."
        case .sessionActivationFailed(let reason):
            return "Could not activate the audio session: \(reason)"
        case .recorderSetupFailed(let reason):
            return "Could not initialise the recorder: \(reason)"
        case .recordingFailed(let reason):
            return "Recording failed: \(reason)"
        case .fileEmpty:
            return "The recorded file was empty."
        case .interrupted:
            return "Recording was interrupted by another audio source."
        }
    }
}
