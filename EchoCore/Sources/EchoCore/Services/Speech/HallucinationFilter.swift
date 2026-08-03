//
//  HallucinationFilter.swift
//  Echo
//
//  Ports the hallucination-guard logic from Android's OpenAICompatibleProvider.kt.
//  Used exclusively by providers that return verbose_json (OpenAI-compatible family).
//
//  Android source of truth:
//    android/.../speech/provider/OpenAICompatibleProvider.kt
//    NO_SPEECH_AVG_THRESHOLD = 0.6
//    NO_SPEECH_MAX_THRESHOLD = 0.8
//    HALLUCINATION_PHRASES    = { "you", "thank you.", ... }
//

import Foundation
import os

/// Stateless, pure-function filter.  Returns `false` when the transcript should
/// be discarded as hallucinated or silent output.
public enum HallucinationFilter {

    // MARK: - Thresholds (Android parity)
    public static let noSpeechAverageThreshold: Double = AppConfig.Hallucination.noSpeechAverageThreshold
    public static let noSpeechMaxThreshold:     Double = AppConfig.Hallucination.noSpeechMaxThreshold

    // MARK: - Known hallucination phrases (Android parity)
    public static let knownPhrases: Set<String> = AppConfig.Hallucination.knownPhrases

    /// Determines whether `text` should be returned to the caller.
    ///
    /// - Parameters:
    ///   - text: Already-trimmed transcript text.
    ///   - segments: The `segments` array from the `verbose_json` response, as
    ///     dictionaries each containing a `no_speech_prob` key.  Pass `nil` or
    ///     empty when the response does not include segment data.
    /// - Returns: `true` when the text passes the filter and should be kept;
    ///            `false` when it should be discarded (return `TranscriptionResult("")`).
    public static func passes(text: String, segments: [[String: Any]]?) -> Bool {
        // ── Step 1: no_speech_prob guard ─────────────────────────────────────
        if let segments, !segments.isEmpty {
            var sum: Double = 0
            var max: Double = 0
            for segment in segments {
                let prob = segment["no_speech_prob"] as? Double ?? 0.0
                sum += prob
                if prob > max { max = prob }
            }
            let avg = sum / Double(segments.count)
            if avg >= noSpeechAverageThreshold || max >= noSpeechMaxThreshold {
                return false
            }
        }

        // ── Step 2: known phrase guard ────────────────────────────────────────
        if knownPhrases.contains(text.lowercased()) {
            return false
        }

        return true
    }
}
