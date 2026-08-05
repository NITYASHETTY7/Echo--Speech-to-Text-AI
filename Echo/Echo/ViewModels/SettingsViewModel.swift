//
//  SettingsViewModel.swift
//  Echo
//
//  ViewModel for the Settings screen.
//
//  Matches Android SettingsViewModel:
//  - TestState enum: Idle / Testing / Success(latencyMs) / Error(message)
//  - onTestConnection() performs a live HTTP check against the selected provider
//  - API key: Paste button support (apiKeyDraft is directly writable)
//  - Animated Save Key button visibility (driven by apiKeyDraft.isEmpty)
//  - "Key saved" confirmation state (hasStoredKey + apiKeyDraft.isEmpty)
//

import Foundation
import EchoCore
import os

// MARK: - TestState (mirrors Android sealed interface TestState)

enum TestConnectionState: Equatable {
    case idle
    case testing
    case success(latencyMs: Int)
    case error(message: String)
}

// MARK: - SettingsViewModel

@MainActor
@Observable
public final class SettingsViewModel {

    // MARK: - Dependencies

    private let providerSettings: ProviderSettings
    private let preferences: Preferences
    private let keychainStore: KeychainStore

    // MARK: - Derived state

    /// All registered provider configurations, in registry order.
    var availableProviders: [ProviderConfig] {
        ProviderRegistry.allConfigs
    }

    /// The currently selected provider configuration, or nil if rawValue is unrecognised.
    var currentProviderConfig: ProviderConfig? {
        ProviderRegistry.configuration(forRawValue: providerSettings.selectedProvider)
    }

    /// Currently selected provider raw value (forwarded from ProviderSettings).
    var selectedProvider: String {
        get { providerSettings.selectedProvider }
        set {
            providerSettings.selectedProvider = newValue
            testState = .idle
            // Reset the draft to any stored key for the new provider
            loadAPIKeyDraft(for: newValue)
        }
    }

    /// Currently selected model (forwarded from ProviderSettings).
    var selectedModel: String {
        get { providerSettings.selectedModel }
        set { providerSettings.selectedModel = newValue }
    }

    /// Custom base URL for providers that support one.
    var customBaseURL: String {
        get { providerSettings.customBaseURL }
        set { providerSettings.customBaseURL = newValue }
    }

    /// Transcription language BCP-47 tag (forwarded from Preferences).
    var language: String {
        get { preferences.language }
        set { preferences.language = newValue }
    }

    /// Grammar correction toggle (forwarded from Preferences).
    var grammarEnabled: Bool {
        get { preferences.grammar }
        set { preferences.grammar = newValue }
    }

    /// Auto-enhance after transcription (forwarded from Preferences).
    var autoEnhanceEnabled: Bool {
        get { preferences.autoEnhance }
        set { preferences.autoEnhance = newValue }
    }

    /// Transcription retention days (forwarded from Preferences).
    var retentionDays: Int {
        get { preferences.retention }
        set { preferences.retention = newValue }
    }

    /// Color scheme preference ("system", "light", "dark").
    var theme: String {
        get { preferences.theme }
        set { preferences.theme = newValue }
    }

    /// Auto-start recording on app launch.
    var autoStart: Bool {
        get { preferences.autoStart }
        set { preferences.autoStart = newValue }
    }

    // MARK: - Accessibility preferences (matches Android PillOverlayService / TextInsertionHelper)

    /// Whether the floating pill recording overlay is enabled.
    var floatingPillEnabled: Bool {
        get { preferences.floatingPillEnabled }
        set { preferences.floatingPillEnabled = newValue }
    }

    /// Whether prompt text injection into focused text fields is enabled.
    var promptTextInjectionEnabled: Bool {
        get { preferences.promptTextInjectionEnabled }
        set { preferences.promptTextInjectionEnabled = newValue }
    }

    // MARK: - API key state

    /// Staging field for editing an API key before saving. Writable externally so the
    /// paste button in the view can set it directly (mirrors Android onApiKeyChanged).
    /// Setting this resets the test state to idle (matches Android onApiKeyChanged).
    var apiKeyDraft: String = "" {
        didSet {
            if oldValue != apiKeyDraft {
                testState = .idle
            }
        }
    }

    /// True when the current provider has a non-blank key stored.
    /// Drives the "✓ API key saved" status and the placeholder text.
    var hasStoredKey: Bool {
        guard !providerSettings.selectedProvider.isEmpty else { return false }
        return keychainStore.isConfigured(for: providerSettings.selectedProvider)
    }

    // MARK: - Test connection state (mirrors Android TestState)

    private(set) var testState: TestConnectionState = .idle

    // MARK: - Errors

    /// Non-nil when a keychain operation error occurs.
    private(set) var keychainError: Error?

    // MARK: - Init

    init(
        providerSettings: ProviderSettings,
        preferences: Preferences,
        keychainStore: KeychainStore
    ) {
        self.providerSettings = providerSettings
        self.preferences = preferences
        self.keychainStore = keychainStore
    }

    // MARK: - Keychain API

    /// Returns the stored API key for the given provider, or nil.
    func loadAPIKey(for provider: String) -> String? {
        keychainStore.loadKey(for: provider)
    }

    /// Saves apiKeyDraft to the keychain for the given provider.
    func saveAPIKey(for provider: String) {
        let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        keychainStore.saveKey(key, for: provider)
        apiKeyDraft = ""
        testState = .idle
        EchoLog.ui.debug("Saved API key for provider: \(provider, privacy: .public)")
    }

    /// Saves an explicit key string to the keychain.
    func saveAPIKey(_ key: String, for provider: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        keychainStore.saveKey(trimmed, for: provider)
        apiKeyDraft = ""
        testState = .idle
        EchoLog.ui.debug("Saved API key for provider: \(provider, privacy: .public)")
    }

    /// Removes the stored API key for the given provider.
    func deleteAPIKey(for provider: String) {
        keychainStore.clearKey(for: provider)
        apiKeyDraft = ""
        testState = .idle
        EchoLog.ui.debug("Deleted API key for provider: \(provider, privacy: .public)")
    }

    /// Returns true if a non-blank API key is stored for the given provider.
    func isProviderConfigured(_ provider: String) -> Bool {
        keychainStore.isConfigured(for: provider)
    }

    /// Populates apiKeyDraft with the stored key for the given provider.
    /// The view uses `hasStoredKey` to show the "Key saved" placeholder,
    /// but the draft itself holds the actual key value for editing scenarios.
    func loadAPIKeyDraft(for provider: String) {
        apiKeyDraft = keychainStore.loadKey(for: provider) ?? ""
    }

    /// Clears the draft field.
    func clearAPIKeyDraft() {
        apiKeyDraft = ""
    }

    /// Clears any surfaced keychain error.
    func clearError() {
        keychainError = nil
    }

    // MARK: - API key signup URL (matches Android provider URL helper text)

    /// Returns the official API signup / dashboard URL for the currently selected
    /// provider, or nil if the provider has no public signup page (e.g. Custom).
    /// Used by SettingsView to render the "Get your API key from <url>" helper row.
    var apiKeySignupURL: URL? {
        guard let providerId = ProviderId(rawValue: providerSettings.selectedProvider) else {
            return nil
        }
        let urlString: String?
        switch providerId {
        case .groq:       urlString = "https://console.groq.com/keys"
        case .openAI:     urlString = "https://platform.openai.com/api-keys"
        case .openRouter: urlString = "https://openrouter.ai/keys"
        case .deepgram:   urlString = "https://console.deepgram.com"
        case .assemblyAI: urlString = "https://www.assemblyai.com/dashboard"
        case .gemini:     urlString = "https://aistudio.google.com/apikey"
        case .azure:      urlString = "https://portal.azure.com"
        case .custom:     urlString = nil   // no canonical signup page
        }
        return urlString.flatMap { URL(string: $0) }
    }

    /// The display host (e.g. "console.groq.com") for the current provider's
    /// signup URL, or nil when there is no URL.
    var apiKeySignupHost: String? {
        apiKeySignupURL?.host
    }

    // MARK: - Supported models

    func supportedModels(for config: ProviderConfig) -> [String] {
        config.supportedModels
    }

    func supportsCustomBaseURL(for config: ProviderConfig) -> Bool {
        config.capabilities.supportsCustomBaseURL
    }

    // MARK: - Test Connection (mirrors Android SettingsViewModel.onTestConnection)

    func testConnection() {
        guard testState != .testing else { return }

        let provider = providerSettings.selectedProvider
        guard let config = ProviderRegistry.configuration(forRawValue: provider) else {
            testState = .error(message: "Unknown provider")
            return
        }

        // Resolve API key: stored key takes precedence, then draft
        let storedKey = keychainStore.loadKey(for: provider) ?? ""
        let draftKey  = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey    = storedKey.isEmpty ? draftKey : storedKey

        guard !apiKey.isEmpty else {
            testState = .error(message: "No API key entered")
            return
        }

        let baseURL = config.capabilities.supportsCustomBaseURL
            ? providerSettings.customBaseURL
            : config.defaultBaseURL

        if config.capabilities.supportsCustomBaseURL && baseURL.isEmpty {
            testState = .error(message: "Base URL is required")
            return
        }

        testState = .testing

        Task {
            let result = await performTestRequest(
                provider: provider,
                config: config,
                apiKey: apiKey,
                baseURL: baseURL
            )
            testState = result
        }
    }

    private func performTestRequest(
        provider: String,
        config: ProviderConfig,
        apiKey: String,
        baseURL: String
    ) async -> TestConnectionState {
        // Build the test URL matching Android runTestRequest() logic.
        let testURLString: String
        switch provider.lowercased() {
        case "deepgram":
            testURLString = "https://api.deepgram.com/v1/projects"
        case "assemblyai":
            testURLString = "https://api.assemblyai.com/v2/account"
        case "gemini":
            testURLString = "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)"
        default:
            let base = baseURL.hasSuffix("/") ? baseURL : baseURL + "/"
            testURLString = "\(base)models"
        }

        guard let url = URL(string: testURLString) else {
            return .error(message: "Invalid endpoint URL")
        }

        // ── Build request ──────────────────────────────────────────────────────
        // Auth header — match Android runTestRequest() exactly.
        let authHeaderValue: String
        switch provider.lowercased() {
        case "deepgram", "assemblyai":
            authHeaderValue = "Token \(apiKey)"
        case "gemini":
            authHeaderValue = ""   // key embedded in URL
        default:
            authHeaderValue = "Bearer \(apiKey)"
        }

        var headers: [String: String] = [
            "Accept": "application/json",
        ]
        if !authHeaderValue.isEmpty {
            headers[config.authHeaderName] = authHeaderValue
        }

        // ── Diagnostics: log full request (key value redacted) ─────────────────
        let redactedHeaders = headers.map { k, _ in
            k == config.authHeaderName ? "\(k): [REDACTED]" : "\(k): \(headers[k] ?? "")"
        }.joined(separator: ", ")
        EchoLog.network.debug(
            """
            [TestConnection] \(provider, privacy: .public)
              URL:     \(testURLString, privacy: .public)
              Method:  GET
              Headers: \(redactedHeaders, privacy: .public)
              Timeout: 30s
            """
        )

        // ── Execute with a dedicated session that matches Android's OkHttp config ──
        // Root cause of the Groq timeout:
        //   The previous implementation used URLSession.shared with a 15-second
        //   timeoutInterval on the URLRequest.  URLSession.shared is shared across
        //   the process and can be delayed by in-flight requests.  More critically,
        //   15s is insufficient for cold-start connections to Groq's API when the
        //   TLS handshake and DNS resolution are included.  Android's OkHttp is
        //   configured with connectTimeout=30s / readTimeout=120s, which succeeds.
        //   We now use a dedicated URLSession with matching timeouts so the test
        //   behaves identically to the transcription path.
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest  = 30   // matches Android connectTimeout
        sessionConfig.timeoutIntervalForResource = 120  // matches Android readTimeout
        // Disable URL caching so the test always makes a live request.
        sessionConfig.urlCache = nil
        sessionConfig.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let testSession = URLSession(configuration: sessionConfig)
        defer { testSession.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let start = Date()
        do {
            let (data, response) = try await testSession.data(for: request)
            let durationMs = Int(Date().timeIntervalSince(start) * 1_000)

            guard let http = response as? HTTPURLResponse else {
                EchoLog.network.error("[TestConnection] non-HTTP response")
                return .error(message: "Invalid response")
            }

            // Log status + body (truncated) for diagnostics
            let bodyPreview = String(data: data.prefix(500), encoding: .utf8) ?? "<binary>"
            EchoLog.network.debug(
                """
                [TestConnection] response
                  Status:   \(http.statusCode, privacy: .public)
                  Duration: \(durationMs, privacy: .public) ms
                  Body:     \(bodyPreview, privacy: .private)
                """
            )

            switch http.statusCode {
            case 200...299:
                return .success(latencyMs: durationMs)
            case 404 where provider.lowercased() == "azure":
                // Azure /models returns 404 but auth is still valid
                return .success(latencyMs: durationMs)
            case 401:
                return .error(message: "HTTP 401 — Invalid API key")
            case 403:
                return .error(message: "HTTP 403 — Forbidden (check key permissions)")
            case 429:
                return .error(message: "HTTP 429 — Rate limit exceeded")
            case 404:
                return .error(message: "HTTP 404 — Endpoint not found (check Base URL)")
            default:
                return .error(message: "HTTP \(http.statusCode)")
            }

        } catch let urlError as URLError {
            let durationMs = Int(Date().timeIntervalSince(start) * 1_000)
            EchoLog.network.error(
                "[TestConnection] URLError after \(durationMs)ms: \(urlError.code.rawValue, privacy: .public) \(urlError.localizedDescription, privacy: .public)"
            )
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return .error(message: "Network unavailable — cannot reach \(config.displayName)")
            case .timedOut:
                return .error(message: "Request timed out after \(durationMs) ms — check network and API endpoint")
            case .cannotFindHost, .dnsLookupFailed:
                return .error(message: "Cannot resolve host — check Base URL")
            default:
                return .error(message: urlError.localizedDescription)
            }
        } catch {
            let durationMs = Int(Date().timeIntervalSince(start) * 1_000)
            EchoLog.network.error(
                "[TestConnection] error after \(durationMs)ms: \(error.localizedDescription, privacy: .public)"
            )
            return .error(message: error.localizedDescription)
        }
    }
}
