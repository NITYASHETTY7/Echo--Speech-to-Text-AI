//
//  AppConfig.swift
//  Echo
//
//  Centralized, environment-agnostic configuration constants.
//
//  These values are ported directly from the Android implementation so that
//  networking timeouts, polling cadence, and silence/hallucination thresholds
//  behave identically across platforms. See:
//    android/app/src/main/java/com/echo/dictation/di/AppModule.kt      (OkHttp timeouts)
//    android/app/src/main/java/com/echo/dictation/service/overlay/PillController.kt (silence threshold)
//    android/app/src/main/java/com/echo/dictation/speech/provider/AssemblyAIProvider.kt (poll interval/attempts)
//    android/app/src/main/java/com/echo/dictation/speech/provider/SpeechProviderFactory.kt (default provider)
//    android/app/src/main/java/com/echo/dictation/data/local/Preferences.kt (settings defaults)
//
//  This type intentionally contains no SwiftUI, UIKit, or platform-service
//  imports so it can be moved into a shared package (EchoCore) in Phase 9
//  without modification.
//

import Foundation

/// Namespace for app-wide configuration constants.
///
/// All values are `static let`s grouped by concern. Nothing here is mutable
/// at runtime — user-adjustable values (selected provider, language, theme,
/// etc.) live in `Preferences` / `ProviderSettings`, not here.
enum AppConfig {

    // MARK: - Networking (mirrors AppModule.kt OkHttpClient)

    enum Network {
        /// DNS + TLS handshake budget on mobile networks.
        static let connectTimeout: TimeInterval = 30

        /// Large audio uploads / AssemblyAI polling reads.
        static let readTimeout: TimeInterval = 120

        /// Uploading long recordings.
        static let writeTimeout: TimeInterval = 120
    }

    // MARK: - Audio recording (mirrors AudioRecorder.kt)

    enum Audio {
        /// Sample rate in Hz used for recording, matching Android's MediaRecorder config.
        static let sampleRateHz: Double = 16_000

        /// Encoder bit rate in bits per second.
        static let bitRate: Int = 128_000

        /// Mono recording.
        static let channelCount: Int = 1

        /// Amplitude/metering poll interval while recording.
        static let amplitudePollInterval: TimeInterval = 0.2
    }

    // MARK: - Silence detection (mirrors PillController.SILENCE_THRESHOLD)

    enum Silence {
        /// Android's linear peak-amplitude threshold (range 0–32767) below which
        /// a recording is discarded as silence before it is sent to a provider.
        static let androidLinearThreshold: Int = 1500
        static let androidLinearMax: Int = 32_767
    }

    // MARK: - AssemblyAI polling (mirrors AssemblyAIProvider.kt)

    enum AssemblyAI {
        /// Maximum number of polls before the transcription is considered timed out.
        static let maxPollAttempts: Int = 60

        /// Delay between polls. 60 × 2s = 2 minutes max, matching Android.
        static let pollInterval: TimeInterval = 2.0
    }

    // MARK: - Hallucination filtering (mirrors OpenAICompatibleProvider.kt)

    enum Hallucination {
        /// Average no_speech_prob across segments at/above which the transcript is discarded.
        static let noSpeechAverageThreshold: Double = 0.6

        /// Peak no_speech_prob across segments at/above which the transcript is discarded.
        static let noSpeechMaxThreshold: Double = 0.8

        /// The fixed transcription prompt sent to bias against hallucinated filler.
        static let transcriptionPrompt = "Echo."

        /// Known hallucinated phrases (lowercased) that are discarded even when
        /// no_speech_prob metadata is unavailable (e.g. non-Whisper responses).
        static let knownPhrases: Set<String> = [
            "you", "thank you.", "thank you", "thanks.", "thanks",
            ".", "..", "...", "bye.", "bye",
            "subtitles by", "subtitles by the amara.org community",
        ]
    }

    // MARK: - Defaults (mirrors ProviderSettings.kt / AppPreferences.kt)

    enum Defaults {
        /// Empty string means "auto-detect" — the provider chooses the language.
        /// Sending "en" to Whisper forces translation of non-English speech into
        /// English, which breaks multilingual transcription.
        static let language = ""
        static let model = "whisper-large-v3-turbo"
        static let retentionDays = 30
        static let grammarEnabled = true
        static let theme = "system"
    }

    // MARK: - App Group (provisioned now, consumed by the Phase 9 keyboard extension)

    enum Sharing {
        /// Placeholder identifier — must match the App Group configured in the
        /// target's Signing & Capabilities once the Keyboard Extension is added.
        static let appGroupIdentifier = "group.com.mirailabs.echo.shared"

        /// Shared Keychain access group, enabling both the app and (later) the
        /// keyboard extension to read the same provider credentials.
        static let keychainAccessGroup = "com.mirailabs.echo.shared"
    }
}
