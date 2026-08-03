//
//  RecordingConfigurationTests.swift
//  EchoTests
//

import Foundation
import AVFoundation
import Testing
@testable import EchoCore

struct RecordingConfigurationTests {

    @Test("Standard configuration has Android-parity sample rate and channel count")
    func androidParityConstants() {
        let config = RecordingConfiguration.standard
        #expect(config.sampleRate == 16_000)
        #expect(config.channelCount == 1)
        #expect(config.bitRate == 128_000)
        #expect(config.fileExtension == "m4a")
        #expect(config.meteringInterval == 0.2)
    }

    @Test("avSettings contains all required AVAudioRecorder keys")
    func avSettingsKeys() {
        let settings = RecordingConfiguration.standard.avSettings
        #expect(settings[AVFormatIDKey] != nil)
        #expect(settings[AVSampleRateKey] != nil)
        #expect(settings[AVNumberOfChannelsKey] != nil)
        #expect(settings[AVEncoderBitRateKey] != nil)
        #expect(settings[AVEncoderAudioQualityKey] != nil)
        #expect(settings[AVSampleRateKey] as? Double == 16_000)
        #expect(settings[AVNumberOfChannelsKey] as? Int == 1)
        #expect(settings[AVEncoderBitRateKey] as? Int == 128_000)
    }

    @Test("newFilename uses timestamp prefix matching Android pattern")
    func filenamePattern() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let filename = RecordingConfiguration.standard.newFilename(at: date)
        #expect(filename.hasPrefix("recording_"))
        #expect(filename.hasSuffix(".m4a"))
        // Timestamp in ms: 1_000_000 * 1000 = 1_000_000_000
        #expect(filename.contains("1000000000"))
    }

    @Test("newFileURL returns a URL inside the recordings directory")
    func fileURLIsInsideRecordingsDirectory() {
        let config = RecordingConfiguration.standard
        let url = config.newFileURL()
        #expect(url.deletingLastPathComponent() == config.recordingsDirectory)
        #expect(url.pathExtension == "m4a")
    }

    @Test("Two filenames generated at different times are different")
    func uniqueFilenames() {
        let config = RecordingConfiguration.standard
        let first = config.newFilename(at: Date(timeIntervalSince1970: 1000))
        let second = config.newFilename(at: Date(timeIntervalSince1970: 2000))
        #expect(first != second)
    }
}
