//
//  WelcomeView.swift
//  Echo
//
//  Native SwiftUI onboarding screen.
//  Mirrors Android's WelcomeOnboardingScreen:
//  - Hero icon + headline + subtitle
//  - Three feature highlight cards (Speech, AI, Cloud)
//  - "Sign in with Google" button
//  - "Skip" text button (continues as guest — NO sign-in required)
//
//  Authentication is OPTIONAL. Guests get full recording/transcription/rewrite
//  capability. Signing in only enables Cloud Sync.
//

import SwiftUI
import EchoCore
import Combine

// MARK: - WelcomeView

struct WelcomeView: View {

    // MARK: - Dependencies

    @Environment(AuthViewModel.self) private var authViewModel

    // MARK: - Callbacks

    /// Called when the user taps "Skip" — marks onboarding complete, no sign-in.
    var onSkip: () -> Void
    /// Called when authentication succeeds (or already authenticated on launch).
    var onAuthenticated: (EchoUser) -> Void

    // MARK: - Local state

    @State private var showError = false

    // MARK: - Body

    var body: some View {
        // GeometryReader lets us scale spacing proportionally on every device —
        // iPhone SE (667 pt tall) to iPhone Pro Max (932 pt tall).
        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Top safe-area spacer — at least 20 pt, scales with screen height
                    Spacer(minLength: max(20, geo.size.height * 0.04))

                    // ── Hero ─────────────────────────────────────────────────
                    heroSection

                    Spacer(minLength: max(24, geo.size.height * 0.05))

                    // ── Feature highlights ───────────────────────────────────
                    featureHighlightsSection
                        .padding(.horizontal, 24)

                    Spacer(minLength: max(24, geo.size.height * 0.05))

                    // ── CTA ──────────────────────────────────────────────────
                    ctaSection
                        .padding(.horizontal, 24)

                    // Bottom safe-area spacer
                    Spacer(minLength: max(20, geo.size.height * 0.04))
                }
                // Ensure the VStack fills at least the full screen height so the
                // content is centred on large devices but scrollable on small ones.
                .frame(minHeight: geo.size.height)
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        // Single .onChange handler for auth state — handles both navigation and error alert.
        // Previously there were two separate .onChange(of: authViewModel.uiState) modifiers,
        // which caused the second to shadow the first on some iOS versions.
        .onChange(of: authViewModel.uiState) { _, newState in
            switch newState {
            case .authenticated(let user):
                showError = false
                onAuthenticated(user)
            case .error:
                showError = true
            default:
                showError = false
            }
        }
        // Alert bound to showError; message reads from current state.
        .alert("Sign-In Failed", isPresented: $showError) {
            Button("OK") { authViewModel.clearError() }
        } message: {
            if case .error(let msg) = authViewModel.uiState {
                Text(msg)
            } else {
                Text("An unexpected error occurred. Please try again.")
            }
        }
    }

    // MARK: - Sections

    private var heroSection: some View {
        VStack(spacing: 16) {
            // Gradient circle with mic icon — matches Android
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 90, height: 90)

                Image(systemName: "mic.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
            }

            Text("Welcome to Echo")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)

            Text("AI-powered dictation, instant rewrites & cross-device cloud sync")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var featureHighlightsSection: some View {
        VStack(spacing: 12) {
            FeatureHighlightRow(
                symbol: "mic.fill",
                title: "Speech to Text",
                description: "Fast, accurate transcription using your chosen speech provider."
            )
            FeatureHighlightRow(
                symbol: "sparkles",
                title: "AI Enhancements",
                description: "Grammar correction, professional rewrites, summaries & action items."
            )
            FeatureHighlightRow(
                symbol: "icloud.and.arrow.up",
                title: "Cloud Sync",
                description: "Your recordings backed up and restored across devices automatically."
            )
        }
    }

    private var ctaSection: some View {
        VStack(spacing: 10) {
            // Loading or sign-in button
            signInButton

            // Skip — always enabled. Continues as guest with full local functionality.
            // Android label: "Skip" (same text, always tappable regardless of auth state)
            Button {
                onSkip()
            } label: {
                Text("Skip for now")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            // NOT disabled during loading — user must always be able to skip out
        }
    }

    @ViewBuilder
    private var signInButton: some View {
        Button {
            // Obtain the presenting UIViewController from the SwiftUI hierarchy.
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let root = scene.windows.first?.rootViewController else { return }
            authViewModel.signInWithGoogle(presenting: root)
        } label: {
            HStack(spacing: 10) {
                if authViewModel.uiState == .loading {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.9)
                    Text("Signing in…")
                        .font(.headline)
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                    Text("Sign in with Google")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16))
        }
        .disabled(authViewModel.uiState == .loading)
    }
}

// MARK: - FeatureHighlightRow

private struct FeatureHighlightRow: View {
    let symbol: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: symbol)
                    .font(.system(size: 18))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    // In-preview stub: guest AuthRepository
    let stubAuth = StubAuthRepository()
    let vm = AuthViewModel(authRepository: stubAuth, preferences: Preferences())
    return WelcomeView(
        onSkip: {},
        onAuthenticated: { _ in }
    )
    .environment(vm)
}

@MainActor
private final class StubAuthRepository: AuthRepository {
    var currentUser: EchoUser? = nil
    var isAuthenticated: Bool = false
    var currentUserPublisher: AnyPublisher<EchoUser?, Never> {
        Just(nil).eraseToAnyPublisher()
    }
    func signInWithGoogleTokens(idToken: String, accessToken: String) async -> Result<EchoUser, Error> {
        .failure(NSError(domain: "stub", code: 0))
    }
    func signOut() async -> Result<Void, Error> { .success(()) }
}
#endif
