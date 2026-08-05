//
//  SettingsView.swift
//  Echo
//
//  Matches Android SettingsScreen:
//  - API key field with Paste button, Show/Hide toggle, Clear button
//  - Animated "Save Key" button appears only when apiKeyDraft is non-blank
//  - "✓ API key saved" confirmation label when key is stored and draft is blank
//  - Test Connection section with TestState: Idle / Testing / Success(latency) / Error
//  - History Retention as Picker with options: 7 / 14 / 30 / 60 / 90 / 365 days (matches Android)
//  - Base URL field for providers that need it
//  - Language, Theme, Grammar, AutoStart sections
//
//  Platform notes:
//  - Uses SwiftUI Form (native iOS) instead of Android custom card layout — acceptable per HIG.
//  - Segmented Picker for Theme matches Android SimpleDropdown but is more HIG-appropriate.
//

import SwiftUI
import EchoCore

struct SettingsView: View {

    // MARK: - Dependencies

    @Environment(\.keychainStore) private var keychainStore
    @Environment(Preferences.self) private var preferences
    @Environment(ProviderSettings.self) private var providerSettings
    @Environment(AuthViewModel.self) private var authViewModel

    // MARK: - State

    @State private var viewModel: SettingsViewModel?
    @State private var showAPIKeyClearedAlert = false
    @State private var apiKeyVisible = false

    // MARK: - Body

    var body: some View {
        Group {
            if let vm = viewModel {
                settingsForm(vm: vm)
            } else {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        // Ensure the Form (which is a scroll container) fills the full screen
        // between the navigation bar and the home indicator on all devices.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if viewModel == nil, let keychain = keychainStore {
                viewModel = SettingsViewModel(
                    providerSettings: providerSettings,
                    preferences: preferences,
                    keychainStore: keychain
                )
                viewModel?.loadAPIKeyDraft(for: providerSettings.selectedProvider)
            }
        }
    }

    // MARK: - Settings form

    @ViewBuilder
    private func settingsForm(vm: SettingsViewModel) -> some View {
        Form {

            // MARK: - Account Section (matches Android ACCOUNT section) ────────

            Section("ACCOUNT") {
                if let user = authViewModel.currentUser {
                    // Signed-in state — show avatar, name, email, sign-out
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Text(user.resolvedDisplayName.prefix(1).uppercased())
                                .font(.headline.bold())
                                .foregroundStyle(Color.accentColor)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.resolvedDisplayName)
                                .font(.subheadline.weight(.semibold))
                            if let email = user.email {
                                Text(email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                    }
                    Button(role: .destructive) {
                        authViewModel.signOut()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } else {
                    // Signed-out / guest state — offer Google Sign-In
                    Button {
                        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                              let root = scene.windows.first?.rootViewController else { return }
                        authViewModel.signInWithGoogle(presenting: root)
                    } label: {
                        Label("Sign in with Google", systemImage: "person.crop.circle.badge.plus")
                    }
                    .disabled(authViewModel.uiState == .loading)

                    if authViewModel.uiState == .loading {
                        HStack {
                            ProgressView().scaleEffect(0.8)
                            Text("Signing in…").font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    if case .error(let msg) = authViewModel.uiState {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Text("Sign in to enable Cloud Sync across devices.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: - Speech AI Section ─────────────────────────────────────

            Section("SPEECH AI") {

                // Provider picker
                Picker("Provider", selection: Binding(
                    get: { vm.selectedProvider },
                    set: { newVal in
                        vm.selectedProvider = newVal
                        apiKeyVisible = false
                        if let config = ProviderRegistry.configuration(forRawValue: newVal) {
                            vm.selectedModel = config.defaultModel
                        }
                    }
                )) {
                    ForEach(vm.availableProviders, id: \.id) { config in
                        Text(config.displayName).tag(config.id.rawValue)
                    }
                }
                .pickerStyle(.menu)
            }

            // MARK: - API Key Section ───────────────────────────────────────

            Section("API KEY") {
                apiKeySection(vm: vm)
            }

            // MARK: - Model Section ─────────────────────────────────────────

            if let config = vm.currentProviderConfig {
                if !config.supportedModels.isEmpty {
                    Section("MODEL") {
                        Picker("Model", selection: Binding(
                            get: { vm.selectedModel },
                            set: { vm.selectedModel = $0 }
                        )) {
                            ForEach(vm.supportedModels(for: config), id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                } else if config.capabilities.supportsCustomModel {
                    Section("MODEL") {
                        TextField("Model name", text: Binding(
                            get: { vm.selectedModel },
                            set: { vm.selectedModel = $0 }
                        ))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    }
                }
            }

            // MARK: - Base URL Section (conditional) ───────────────────────

            if let config = vm.currentProviderConfig,
               vm.supportsCustomBaseURL(for: config) {
                Section("BASE URL") {
                    TextField("https://your-endpoint.com/v1/", text: Binding(
                        get: { vm.customBaseURL },
                        set: { vm.customBaseURL = $0 }
                    ))
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                }
            }

            // MARK: - Test Connection Section ──────────────────────────────

            Section("CONNECTION") {
                testConnectionSection(vm: vm)
            }

            // MARK: - General Section ──────────────────────────────────────

            Section("GENERAL") {

                // Language
                Picker("Language", selection: Binding(
                    get: { vm.language },
                    set: { vm.language = $0 }
                )) {
                    ForEach(SupportedLanguage.allCases, id: \.tag) { lang in
                        Text(lang.displayName).tag(lang.tag)
                    }
                }
                .pickerStyle(.menu)

                // History Retention — matches Android options exactly: 7/14/30/60/90/365 days
                Picker("History Retention", selection: Binding(
                    get: { vm.retentionDays },
                    set: { vm.retentionDays = $0 }
                )) {
                    ForEach(RetentionOption.allCases, id: \.days) { option in
                        Text(option.label).tag(option.days)
                    }
                }
                .pickerStyle(.menu)

                // Theme
                Picker("Theme", selection: Binding(
                    get: { vm.theme },
                    set: { vm.theme = $0 }
                )) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)

                // Grammar correction
                Toggle("Grammar Correction", isOn: Binding(
                    get: { vm.grammarEnabled },
                    set: { vm.grammarEnabled = $0 }
                ))

                // Auto-enhance
                Toggle("Auto-Enhance After Transcription", isOn: Binding(
                    get: { vm.autoEnhanceEnabled },
                    set: { vm.autoEnhanceEnabled = $0 }
                ))

                // Auto-start
                Toggle("Auto-Start on Launch", isOn: Binding(
                    get: { vm.autoStart },
                    set: { vm.autoStart = $0 }
                ))
            }

            // MARK: - Accessibility Section ────────────────────────────────
            // Matches Android's PillOverlayService + TextInsertionHelper features.

            Section("ACCESSIBILITY") {

                // Floating Pill — matches Android PillOverlayService enable/disable
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: Binding(
                        get: { vm.floatingPillEnabled },
                        set: { vm.floatingPillEnabled = $0 }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Floating Mic Pill")
                                .font(.body)
                            Text("Show a draggable microphone button on screen while recording")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Prompt Text Injection — matches Android TextInsertionHelper
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: Binding(
                        get: { vm.promptTextInjectionEnabled },
                        set: { vm.promptTextInjectionEnabled = $0 }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Prompt Text Injection")
                                .font(.body)
                            Text("Automatically insert transcribed text into the active text field")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // MARK: - About Section ─────────────────────────────────────────

            Section("ABOUT") {
                LabeledContent("Version", value: Bundle.main.appVersion)
                LabeledContent("Build", value: Bundle.main.buildNumber)
            }

            // MARK: - Developer Section (DEBUG builds only) ─────────────────
            // Provides a clean way to return to the Welcome screen during
            // development WITHOUT deleting the app. Compiled out of Release
            // builds via #if DEBUG, so production Firebase session persistence
            // is never affected.
            #if DEBUG
            Section("DEVELOPER") {
                Button(role: .destructive) {
                    // 1. Sign out of Firebase (clears the persisted session).
                    authViewModel.signOut()
                    // 2. Reset onboarding so RootView shows WelcomeView again.
                    //    RootView observes preferences.onboardingCompleted, so
                    //    this takes effect immediately.
                    preferences.onboardingCompleted = false
                } label: {
                    Label("Reset Session (Development)", systemImage: "arrow.counterclockwise.circle")
                }
                Text("Signs out and returns to the Welcome screen. Debug builds only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            #endif
        }
        .alert("API Key Cleared", isPresented: $showAPIKeyClearedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The API key has been removed from the keychain.")
        }
        .alert("Keychain Error", isPresented: Binding(
            get: { vm.keychainError != nil },
            set: { if !$0 { vm.clearError() } }
        )) {
            Button("OK", role: .cancel) { vm.clearError() }
        } message: {
            Text(vm.keychainError?.localizedDescription ?? "A keychain error occurred.")
        }
    }

    // MARK: - API key section (matches Android ApiKeyField)

    @ViewBuilder
    private func apiKeySection(vm: SettingsViewModel) -> some View {
        // Text field row with Paste / Show / Clear inline buttons
        HStack(spacing: 0) {
            Group {
                if apiKeyVisible {
                    TextField(
                        vm.hasStoredKey
                            ? "Key saved — enter new key to replace"
                            : "Enter your API key",
                        text: Binding(
                            get: { vm.apiKeyDraft },
                            set: { vm.apiKeyDraft = $0 }
                        )
                    )
                } else {
                    SecureField(
                        vm.hasStoredKey
                            ? "Key saved — enter new key to replace"
                            : "Enter your API key",
                        text: Binding(
                            get: { vm.apiKeyDraft },
                            set: { vm.apiKeyDraft = $0 }
                        )
                    )
                }
            }
            .textContentType(.password)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)

            // Paste button — matches Android ContentPaste icon button
            Button {
                if let clip = UIPasteboard.general.string, !clip.isEmpty {
                    vm.apiKeyDraft = clip
                }
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Paste API key")
            .padding(.leading, 8)

            // Show/hide toggle — matches Android Visibility toggle
            Button {
                apiKeyVisible.toggle()
            } label: {
                Image(systemName: apiKeyVisible ? "eye.slash" : "eye")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(apiKeyVisible ? "Hide key" : "Show key")
            .padding(.leading, 6)

            // Clear — shown when draft is non-empty or key is stored (matches Android Clear button)
            if !vm.apiKeyDraft.isEmpty || vm.hasStoredKey {
                Button {
                    vm.deleteAPIKey(for: vm.selectedProvider)
                    vm.clearAPIKeyDraft()
                    showAPIKeyClearedAlert = true
                    apiKeyVisible = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear API key")
                .padding(.leading, 6)
            }
        }

        // Animated "Save Key" button — visible only when draft is non-blank (matches Android AnimatedVisibility)
        if !vm.apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Button {
                vm.saveAPIKey(for: vm.selectedProvider)
                apiKeyVisible = false
            } label: {
                Label("Save Key", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.604, green: 0.659, blue: 1.0)) // echoPrimary
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }

        // "✓ API key saved" label — shown when key is stored (matches Android "✓ API key saved")
        if vm.hasStoredKey {
            Label("API key saved", systemImage: "checkmark.shield.fill")
                .font(.caption)
                .foregroundStyle(.green)
        }

        // Helper text — "Get your API key from <url>" (matches Android ApiKeyField helper)
        // Hidden when the provider has no public signup page (e.g. Custom).
        if let url = vm.apiKeySignupURL, let host = vm.apiKeySignupHost {
            HStack(spacing: 4) {
                Text("Get your API key from")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    UIApplication.shared.open(url)
                } label: {
                    Text(host)
                        .font(.caption)
                        .foregroundStyle(Color(red: 0.604, green: 0.659, blue: 1.0))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Open \(host) in browser")
            }
        }
    }

    // MARK: - Test Connection section (matches Android TestConnectionSection)

    @ViewBuilder
    private func testConnectionSection(vm: SettingsViewModel) -> some View {
        Button {
            vm.testConnection()
        } label: {
            HStack {
                if vm.testState == .testing {
                    ProgressView()
                        .scaleEffect(0.85)
                        .tint(Color(red: 0.604, green: 0.659, blue: 1.0))
                    Text("Testing…")
                        .foregroundStyle(Color(red: 0.604, green: 0.659, blue: 1.0))
                } else {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("Test Provider")
                        .foregroundStyle(Color(red: 0.604, green: 0.659, blue: 1.0))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .disabled(vm.testState == .testing)
        .buttonStyle(.borderless)

        // Result row — animated, matches Android AnimatedVisibility result section
        switch vm.testState {
        case .success(let latencyMs):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Connected (\(latencyMs) ms)")
                    .font(.callout)
                    .foregroundStyle(.green)
            }
            .transition(.opacity)

        case .error(let message):
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            .transition(.opacity)

        case .idle, .testing:
            EmptyView()
        }
    }
}

// MARK: - Retention options (matches Android retentionOptions list: 7/14/30/60/90/365)

private enum RetentionOption: CaseIterable {
    case days7, days14, days30, days60, days90, days365

    var days: Int {
        switch self {
        case .days7:   return 7
        case .days14:  return 14
        case .days30:  return 30
        case .days60:  return 60
        case .days90:  return 90
        case .days365: return 365
        }
    }

    var label: String { "\(days) days" }
}

// MARK: - Supported Languages

private struct SupportedLanguage {
    let tag: String
    let displayName: String

    static let allCases: [SupportedLanguage] = [
        SupportedLanguage(tag: "",   displayName: "Auto-detect"),
        SupportedLanguage(tag: "en", displayName: "English"),
        SupportedLanguage(tag: "hi", displayName: "Hindi"),
        SupportedLanguage(tag: "es", displayName: "Spanish"),
        SupportedLanguage(tag: "fr", displayName: "French"),
        SupportedLanguage(tag: "de", displayName: "German"),
        SupportedLanguage(tag: "it", displayName: "Italian"),
        SupportedLanguage(tag: "pt", displayName: "Portuguese"),
        SupportedLanguage(tag: "zh", displayName: "Chinese"),
        SupportedLanguage(tag: "ja", displayName: "Japanese"),
        SupportedLanguage(tag: "ko", displayName: "Korean"),
        SupportedLanguage(tag: "ar", displayName: "Arabic"),
        SupportedLanguage(tag: "ru", displayName: "Russian"),
        SupportedLanguage(tag: "nl", displayName: "Dutch"),
        SupportedLanguage(tag: "tr", displayName: "Turkish"),
    ]
}

// MARK: - Bundle helpers

private extension Bundle {
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    var buildNumber: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}
