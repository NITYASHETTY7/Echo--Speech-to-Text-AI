//
//  Logger.swift
//  Echo
//
//  Thin OSLog wrapper providing category-scoped loggers plus a redaction
//  helper for sensitive HTTP header values.
//
//  Mirrors:
//    android/.../EchoApplication.kt          (Timber.plant)
//    android/.../di/AppModule.kt              (HttpLoggingInterceptor redaction regex)
//
//  No SwiftUI/UIKit dependency — safe to relocate into EchoCore in Phase 9.
//

import Foundation
import OSLog

/// Centralized logging facility. Wraps `os.Logger` with named categories that
/// mirror the Android `TAG` constants used throughout the Kotlin codebase,
/// and a redaction utility so API keys are never written to logs.
enum EchoLog {

    /// The bundle subsystem used for all loggers, following Apple's convention.
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.mirailabs.echo"

    // MARK: - Category loggers

    /// General app lifecycle / composition-root logging.
    static let app = Logger(subsystem: subsystem, category: "App")

    /// Audio recording pipeline (AudioRecorder, AudioFileManager, SilenceDetector).
    static let audio = Logger(subsystem: subsystem, category: "Audio")

    /// Networking (HTTPClient, MultipartFormData).
    static let network = Logger(subsystem: subsystem, category: "Network")

    /// Provider selection/config (ProviderRegistry, ProviderFactory).
    static let providers = Logger(subsystem: subsystem, category: "Providers")

    /// Individual AI provider implementations (Groq, OpenAI, Deepgram, ...).
    static let ai = Logger(subsystem: subsystem, category: "AI")

    /// End-to-end transcription pipeline (TranscriptionService, HallucinationFilter).
    static let transcription = Logger(subsystem: subsystem, category: "Transcription")

    /// Persistence (TranscriptionStore, Keychain, Preferences).
    static let storage = Logger(subsystem: subsystem, category: "Storage")

    /// SwiftUI view models and view-level events.
    static let ui = Logger(subsystem: subsystem, category: "UI")

    // MARK: - Redaction

    /// Redacts sensitive HTTP header values from a raw header line or full
    /// request/response dump before it is logged.
    ///
    /// Mirrors the Android regex redaction applied in `AppModule.okHttpClient()`:
    /// `Authorization`, `x-goog-api-key`, and `api-key` header values are replaced
    /// with `[REDACTED]`, regardless of case, so provider credentials never reach
    /// the system log — including in crash reports or sysdiagnoses.
    ///
    /// - Parameter message: A raw log line (e.g. an HTTP header block) that may
    ///   contain one or more sensitive header values.
    /// - Returns: The same message with sensitive header values replaced.
    static func redactingSensitiveHeaders(_ message: String) -> String {
        var result = message
        for pattern in sensitiveHeaderPatterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: "$1[REDACTED]",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return result
    }

    /// Regex patterns matching a header name + its value, capturing everything
    /// up to (but not including) the value in group 1 so it can be preserved
    /// while the value itself is replaced.
    private static let sensitiveHeaderPatterns: [String] = [
        #"(?i)(authorization:\s*)[^\r\n]+"#,
        #"(?i)(x-goog-api-key:\s*)[^\r\n]+"#,
        #"(?i)(api-key:\s*)[^\r\n]+"#,
    ]
}
