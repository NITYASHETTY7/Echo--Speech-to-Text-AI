//
//  RecordingState.swift
//  Echo
//
//  State machine for the audio recording lifecycle.
//

import Foundation

public enum RecordingState: Equatable, Sendable {
    /// No recording in progress and no session is active.
    case idle

    /// Permission prompt has been shown; waiting for the user's answer.
    case requestingPermission

    /// Session is configured, permission is granted, recorder is ready to start.
    case ready

    /// AVAudioRecorder is actively capturing audio.
    case recording

    /// Recording has been paused (AVAudioRecorder.pause).
    case paused

    /// Stop was requested; recorder is flushing and writing the final file.
    case stopping

    /// Recording finished successfully and a valid audio file was produced.
    case completed(RecordingResult)

    /// A terminal error occurred during setup, recording, or stop.
    case failed(RecordingError)

    public var isActive: Bool {
        switch self {
        case .recording, .paused: return true
        default: return false
        }
    }

    public var canStart: Bool {
        switch self {
        case .ready, .completed, .failed: return true
        default: return false
        }
    }

    public var canStop: Bool {
        switch self {
        case .recording, .paused: return true
        default: return false
        }
    }

    public var canPause: Bool {
        if case .recording = self { return true }
        return false
    }

    public var canResume: Bool {
        if case .paused = self { return true }
        return false
    }

    // Equatable — associated-value cases compare by tag only.
    public static func == (lhs: RecordingState, rhs: RecordingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.requestingPermission, .requestingPermission),
             (.ready, .ready),
             (.recording, .recording),
             (.paused, .paused),
             (.stopping, .stopping):
            return true
        case (.completed(let l), .completed(let r)):
            return l == r
        case (.failed(let l), .failed(let r)):
            return l == r
        default:
            return false
        }
    }
}
