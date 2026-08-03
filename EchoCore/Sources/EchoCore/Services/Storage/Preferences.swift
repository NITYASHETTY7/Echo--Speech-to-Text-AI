//
//  Preferences.swift
//  Echo
//
//  UserDefaults-backed app preferences corresponding to Android's
//  data.local.AppPreferences.
//
//  Observation note (critical):
//  ─────────────────────────────────────────────────────────────────────────────
//  Every public property below is a COMPUTED property whose real storage is
//  UserDefaults.  The @Observable macro only auto-instruments STORED properties
//  — it cannot see computed ones.  Without help, reading `preferences.theme`
//  inside a SwiftUI `body` would NOT register the view as an observer, and
//  writing `preferences.theme = …` would NOT notify SwiftUI.  That is exactly
//  what broke the theme switch, Google-Sign-In navigation, and "Skip for now":
//  RootView never re-rendered when `theme` / `onboardingCompleted` changed.
//
//  Fix: manually drive the observation registrar in each accessor using the
//  macro-generated `access(keyPath:)` (in getters) and `withMutation(keyPath:)`
//  (in setters).  This is Apple's documented pattern for @Observable classes
//  whose storage lives outside the object (UserDefaults, Keychain, etc.) and
//  makes every property fully observable while keeping UserDefaults persistence.
//  ─────────────────────────────────────────────────────────────────────────────

import Foundation
import Observation

@MainActor
@Observable
public final class Preferences {
    @ObservationIgnored private let defaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults
    }

    public var language: String {
        get {
            access(keyPath: \.language)
            return defaults.string(forKey: Keys.language) ?? AppConfig.Defaults.language
        }
        set { withMutation(keyPath: \.language) { defaults.set(newValue, forKey: Keys.language) } }
    }

    public var model: String {
        get {
            access(keyPath: \.model)
            return defaults.string(forKey: Keys.model) ?? AppConfig.Defaults.model
        }
        set { withMutation(keyPath: \.model) { defaults.set(newValue, forKey: Keys.model) } }
    }

    public var retention: Int {
        get {
            access(keyPath: \.retention)
            return defaults.object(forKey: Keys.retention) as? Int ?? AppConfig.Defaults.retentionDays
        }
        set { withMutation(keyPath: \.retention) { defaults.set(newValue, forKey: Keys.retention) } }
    }

    public var grammar: Bool {
        get {
            access(keyPath: \.grammar)
            return defaults.object(forKey: Keys.grammar) as? Bool ?? AppConfig.Defaults.grammarEnabled
        }
        set { withMutation(keyPath: \.grammar) { defaults.set(newValue, forKey: Keys.grammar) } }
    }

    public var theme: String {
        get {
            access(keyPath: \.theme)
            return defaults.string(forKey: Keys.theme) ?? AppConfig.Defaults.theme
        }
        set { withMutation(keyPath: \.theme) { defaults.set(newValue, forKey: Keys.theme) } }
    }

    public var autoStart: Bool {
        get {
            access(keyPath: \.autoStart)
            return defaults.object(forKey: Keys.autoStart) as? Bool ?? false
        }
        set { withMutation(keyPath: \.autoStart) { defaults.set(newValue, forKey: Keys.autoStart) } }
    }

    public var floatingPillX: Int {
        get {
            access(keyPath: \.floatingPillX)
            return defaults.object(forKey: Keys.floatingPillX) as? Int ?? Int.min
        }
        set { withMutation(keyPath: \.floatingPillX) { defaults.set(newValue, forKey: Keys.floatingPillX) } }
    }

    public var floatingPillY: Int {
        get {
            access(keyPath: \.floatingPillY)
            return defaults.object(forKey: Keys.floatingPillY) as? Int ?? Int.min
        }
        set { withMutation(keyPath: \.floatingPillY) { defaults.set(newValue, forKey: Keys.floatingPillY) } }
    }

    // MARK: - Accessibility features (matches Android PillOverlayService / TextInsertionHelper)

    /// Whether the floating pill recording button overlay is enabled.
    public var floatingPillEnabled: Bool {
        get {
            access(keyPath: \.floatingPillEnabled)
            return defaults.object(forKey: Keys.floatingPillEnabled) as? Bool ?? false
        }
        set { withMutation(keyPath: \.floatingPillEnabled) { defaults.set(newValue, forKey: Keys.floatingPillEnabled) } }
    }

    /// Whether prompt text injection into the focused text field is enabled.
    public var promptTextInjectionEnabled: Bool {
        get {
            access(keyPath: \.promptTextInjectionEnabled)
            return defaults.object(forKey: Keys.promptTextInjectionEnabled) as? Bool ?? false
        }
        set { withMutation(keyPath: \.promptTextInjectionEnabled) { defaults.set(newValue, forKey: Keys.promptTextInjectionEnabled) } }
    }

    // ── V2 additions ──────────────────────────────────────────────────────────

    /// True after the user has either signed in or tapped Skip on the Welcome screen.
    public var onboardingCompleted: Bool {
        get {
            access(keyPath: \.onboardingCompleted)
            return defaults.bool(forKey: Keys.onboardingCompleted)
        }
        set { withMutation(keyPath: \.onboardingCompleted) { defaults.set(newValue, forKey: Keys.onboardingCompleted) } }
    }

    /// BCP-47 tag for the default translation target language (e.g. "es", "fr").
    public var translationLanguage: String {
        get {
            access(keyPath: \.translationLanguage)
            return defaults.string(forKey: Keys.translationLanguage) ?? "Spanish"
        }
        set { withMutation(keyPath: \.translationLanguage) { defaults.set(newValue, forKey: Keys.translationLanguage) } }
    }

    // ── V3 additions ──────────────────────────────────────────────────────────

    /// Auto-enhance transcripts after recording (off by default).
    public var autoEnhance: Bool {
        get {
            access(keyPath: \.autoEnhance)
            return defaults.object(forKey: Keys.autoEnhance) as? Bool ?? false
        }
        set { withMutation(keyPath: \.autoEnhance) { defaults.set(newValue, forKey: Keys.autoEnhance) } }
    }

    /// Output language for AI Custom Rewrites (default "English").
    public var rewriteOutputLanguage: String {
        get {
            access(keyPath: \.rewriteOutputLanguage)
            return defaults.string(forKey: Keys.rewriteOutputLanguage) ?? "English"
        }
        set { withMutation(keyPath: \.rewriteOutputLanguage) { defaults.set(newValue, forKey: Keys.rewriteOutputLanguage) } }
    }

    private enum Keys {
        static let language = "language"
        static let model = "model"
        static let retention = "retention"
        static let grammar = "grammar"
        static let theme = "theme"
        static let autoStart = "auto_start"
        static let floatingPillX = "floating_pill_x"
        static let floatingPillY = "floating_pill_y"
        static let floatingPillEnabled = "floating_pill_enabled"
        static let promptTextInjectionEnabled = "prompt_text_injection_enabled"
        static let onboardingCompleted = "onboarding_completed"
        static let translationLanguage = "translation_language"
        static let autoEnhance = "auto_enhance"
        static let rewriteOutputLanguage = "rewrite_output_language"
    }
}
