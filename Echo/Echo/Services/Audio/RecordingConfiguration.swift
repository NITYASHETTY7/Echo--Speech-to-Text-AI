//
//  RecordingConfiguration.swift
//  Echo
//
//  Single source of truth for audio capture parameters.
//
//  Android source of truth:
//    AudioRecorder.kt: SAMPLE_RATE_HZ=16000, BIT_RATE=128000, CHANNELS=1
//    MediaRecorder format: MPEG_4 / AAC → .m4a output
//
//  No SwiftUI or UIKit imports.
//

import Foundation
import AVFoundation

struct RecordingConfiguration: Equatable, Sendable {

    // MARK: - Format

    /// AVAudioRecorder settings dictionary key for the audio format.
    let formatID: AudioFormatID

    /// Sample rate in Hz — matches Android's SAMPLE_RATE_HZ = 16 000.
    let sampleRate: Double

    /// Number of channels — matches Android's CHANNELS = 1 (mono).
    let channelCount: Int

    /// Encoder bit rate in bps — matches Android's BIT_RATE = 128 000.
    let bitRate: Int

    /// Audio quality used by AVAudioRecorder.
    let encoderQuality: AVAudioQuality

    // MARK: - Storage

    /// The directory under which new recordings are placed.
    let recordingsDirectory: URL

    /// File extension for output files (no leading dot).
    let fileExtension: String

    // MARK: - Metering

    /// Interval between peak-power polls in seconds.
    /// Android polls every 200 ms (AMPLITUDE_POLL_MS = 200).
    let meteringInterval: TimeInterval

    // MARK: - Defaults

    static let standard = RecordingConfiguration(
        formatID: kAudioFormatMPEG4AAC,
        sampleRate: AppConfig.Audio.sampleRateHz,
        channelCount: AppConfig.Audio.channelCount,
        bitRate: AppConfig.Audio.bitRate,
        encoderQuality: .high,
        recordingsDirectory: RecordingConfiguration.defaultRecordingsDirectory(),
        fileExtension: "m4a",
        meteringInterval: AppConfig.Audio.amplitudePollInterval
    )

    // MARK: - AVAudioRecorder settings

    /// Settings dictionary passed directly to AVAudioRecorder(url:settings:).
    var avSettings: [String: Any] {
        [
            AVFormatIDKey: Int(formatID),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVEncoderBitRateKey: bitRate,
            AVEncoderAudioQualityKey: encoderQuality.rawValue,
        ]
    }

    // MARK: - Filename generation

    /// Generates a timestamped filename, matching Android's
    /// `recording_${System.currentTimeMillis()}.m4a` pattern.
    ///
    /// When `suffix` is non-zero it is appended before the extension
    /// (`recording_<ms>_<suffix>.m4a`) so a unique name can still be produced
    /// if two calls land within the same millisecond. `suffix == 0` preserves
    /// the exact Android-parity filename.
    func newFilename(at date: Date = .now, suffix: Int = 0) -> String {
        let ms = Int64(date.timeIntervalSince1970 * 1000)
        if suffix == 0 {
            return "recording_\(ms).\(fileExtension)"
        }
        return "recording_\(ms)_\(suffix).\(fileExtension)"
    }

    /// Full URL for a new recording file.
    func newFileURL(at date: Date = .now, suffix: Int = 0) -> URL {
        recordingsDirectory.appending(path: newFilename(at: date, suffix: suffix), directoryHint: .notDirectory)
    }

    // MARK: - Private helpers

    private static func defaultRecordingsDirectory() -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(filePath: NSTemporaryDirectory())
        // directoryHint: .isDirectory appends a trailing slash so that
        // fileURL.deletingLastPathComponent() == recordingsDirectory holds under
        // URL structural equality (which is used by #expect and == comparisons).
        return base.appending(path: "recordings", directoryHint: .isDirectory)
    }
}
