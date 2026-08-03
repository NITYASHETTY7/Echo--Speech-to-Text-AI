//
//  LanguageDetector.swift
//  EchoCore
//
//  Lightweight spoken-language detection for transcripts.
//
//  Uses Apple's on-device NLLanguageRecognizer — no network, no dependency.
//  Maps ISO 639-1 language codes returned by NaturalLanguage to the display
//  names used by SupportedRewriteLanguage in the app.
//
//  Design:
//  - detect(text:) → display-name String (e.g. "Kannada", "English")
//  - Falls back to "English" on failure or unrecognised code
//  - Only used to auto-seed the output language dropdown — never modifies
//    the Original transcript
//

import Foundation
import NaturalLanguage

// MARK: - LanguageDetector

public enum LanguageDetector {

    // MARK: - Public API

    /// Detects the dominant language of `text` and returns the display name
    /// used by SupportedRewriteLanguage (e.g. "Kannada", "English", "Japanese").
    ///
    /// Returns `"English"` when:
    ///  - text is empty or shorter than 10 characters (too little signal)
    ///  - the recogniser's confidence is below 0.4
    ///  - the detected code doesn't map to a supported language
    public static func detect(text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Need at least a few words for a reliable result.
        guard trimmed.count >= 10 else { return "English" }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)

        guard
            let lang = recognizer.dominantLanguage,
            lang != .undetermined
        else { return "English" }

        // Check confidence — low confidence means we can't trust the result.
        let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
        let confidence = hypotheses[lang] ?? 0
        guard confidence >= 0.4 else { return "English" }

        return displayName(for: lang.rawValue) ?? "English"
    }

    // MARK: - BCP-47 → display name mapping

    /// Maps an ISO 639-1 / BCP-47 language code to the display name used by
    /// SupportedRewriteLanguage.  Only languages present in that enum are listed.
    private static func displayName(for code: String) -> String? {
        // NLLanguage rawValues are BCP-47 strings (e.g. "en", "kn", "hi")
        switch code {
        case "en":          return "English"
        case "hi":          return "Hindi"
        case "kn":          return "Kannada"
        case "ml":          return "Malayalam"
        case "ta":          return "Tamil"
        case "te":          return "Telugu"
        case "mr":          return "Marathi"
        case "gu":          return "Gujarati"
        case "pa":          return "Punjabi"
        case "bn":          return "Bengali"
        case "ur":          return "Urdu"
        case "es":          return "Spanish"
        case "fr":          return "French"
        case "de":          return "German"
        case "it":          return "Italian"
        case "pt":          return "Portuguese"
        case "ja":          return "Japanese"
        case "ko":          return "Korean"
        case "zh-Hans",
             "zh-Hant",
             "zh":          return "Chinese (Simplified)"
        default:            return nil
        }
    }
}
