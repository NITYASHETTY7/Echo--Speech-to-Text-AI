//
//  EchoApp.swift
//  Echo
//
//  App entry point. Wires auth, cloud sync, and AI pipeline stacks.
//
//  Navigation regression fix:
//  ─────────────────────────────────────────────────────────────────────────────
//  Previous version initialised AuthViewModel (and three other services) lazily
//  inside `body` using the `@State ?? { create; DispatchQueue.main.async { store } }()`
//  pattern.  This caused multiple problems:
//
//  1. Multiple render cycles on launch — each of the four lazy inits posted a
//     `DispatchQueue.main.async` mutation that triggered another `EchoApp.body`
//     evaluation.  On those intermediate renders `authViewModel` was still nil,
//     so a NEW `AuthViewModel` was created and immediately discarded.  The final
//     surviving `AuthViewModel` was an arbitrary one from the last intermediate
//     render.
//
//  2. The discarded `AuthViewModel` instances had their Combine subscriptions
//     torn down and recreated, leaving the final instance in an unpredictable
//     state.  In practice this meant:
//       • `WelcomeView.onChange(of: authViewModel.uiState)` never fired after
//         Google Sign-In because the `authViewModel` in the environment was a
//         different object from the one whose `uiState` changed.
//       • The `onSkip` closure captured a `preferences` reference that WAS the
//         right object, but the re-render never happened because the observation
//         chain was broken by the intermediate renders.
//
//  Fix: create ALL services synchronously in `init()` as `let` constants.
//  `EchoApp.init()` is called on the main thread before any SwiftUI rendering
//  begins, so accessing `modelContainer.mainContext` is safe here.
//  `body` becomes a pure view builder that injects already-created objects —
//  no lazy logic, no async posts, no intermediate renders.
//  ─────────────────────────────────────────────────────────────────────────────

import SwiftUI
import SwiftData
import EchoCore
import FirebaseCore
import GoogleSignIn

@main
struct EchoApp: App {

    // MARK: - All services created synchronously in init()

    private let modelContainer:        ModelContainer
    private let keychainStore:         KeychainStore
    private let preferences:           Preferences
    private let providerSettings:      ProviderSettings
    private let sessionManager:        SessionManagerImpl
    private let authRemoteDataSource:  FirebaseAuthService
    private let authRepository:        AuthRepositoryImpl
    private let transcriptionStore:    TranscriptionStore
    private let aiService:             AIService
    private let authViewModel:         AuthViewModel

    // syncService is kept as @State because FirestoreSyncService is
    // @MainActor and we need to wire its onSignedIn callback after creation,
    // but it can be initialised immediately too.
    private let syncService:           FirestoreSyncService

    // MARK: - Init

    init() {
        AppEnvironment.bootstrap()
        FirebaseApp.configure()

        // ── Google Sign-In ────────────────────────────────────────────────────
        if let clientID = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }

        // ── SwiftData ─────────────────────────────────────────────────────────
        let container: ModelContainer
        do {
            container = try TranscriptionStore.makeModelContainer()
        } catch {
            fatalError("Cannot create Echo SwiftData container: \(error)")
        }
        modelContainer = container

        // ── Core services ─────────────────────────────────────────────────────
        let ks  = KeychainStore()
        let prf = Preferences()
        let ps  = ProviderSettings()
        keychainStore    = ks
        preferences      = prf
        providerSettings = ps

        // ── Auth stack ────────────────────────────────────────────────────────
        let session = SessionManagerImpl()
        let remote  = FirebaseAuthService()
        let repo    = AuthRepositoryImpl(remoteDataSource: remote, sessionManager: session)
        sessionManager       = session
        authRemoteDataSource = remote
        authRepository       = repo

        // ── Transcription store ───────────────────────────────────────────────
        // modelContainer.mainContext is safe to access here because EchoApp.init()
        // runs synchronously on the main thread before any SwiftUI evaluation.
        let store = TranscriptionStore(modelContext: container.mainContext)
        transcriptionStore = store

        // ── AI service stack ──────────────────────────────────────────────────
        let factory = ProviderFactory(keychainStore: ks, providerSettings: ps)
        let aiRepo  = AIRepositoryImpl(providerFactory: factory, store: store)
        let ai      = AIService(aiRepository: aiRepo)
        aiService   = ai

        // ── Auth ViewModel ────────────────────────────────────────────────────
        // Stable single instance — no re-creation across renders.
        let authVM = AuthViewModel(authRepository: repo, preferences: prf)
        authViewModel = authVM

        // ── Cloud sync ────────────────────────────────────────────────────────
        let sync = FirestoreSyncService(store: store, sessionManager: session)
        syncService = sync

        // Wire sign-in hook after all services are constructed.
        repo.onSignedIn = { [weak sync] _ in
            await sync?.restoreHistory()
            await sync?.triggerSync()
        }
    }

    // MARK: - Scene

    var body: some Scene {
        WindowGroup {
            RootView(preferences: preferences)
                .withAppEnvironment(
                    preferences: preferences,
                    providerSettings: providerSettings,
                    keychainStore: keychainStore,
                    transcriptionStore: transcriptionStore,
                    authViewModel: authViewModel,
                    aiService: aiService
                )
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIApplication.willEnterForegroundNotification
                    )
                ) { _ in Task { await syncService.triggerSync() } }
                .onOpenURL { url in GIDSignIn.sharedInstance.handle(url) }
        }
        .modelContainer(modelContainer)
    }
}

// MARK: - RootView

private struct RootView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(Preferences.self)   private var preferences

    init(preferences: Preferences) {}

    var body: some View {
        // Read preferences.theme DIRECTLY inside body so SwiftUI's @Observable
        // access tracking registers this view as a dependent of preferences.theme.
        let colorScheme: ColorScheme? = {
            switch preferences.theme {
            case "light": return .light
            case "dark":  return .dark
            default:      return nil
            }
        }()

        Group {
            if preferences.onboardingCompleted {
                ContentView()
            } else {
                WelcomeView(
                    onSkip: {
                        // Flow A / Flow E: Skip → Guest Mode → History
                        preferences.onboardingCompleted = true
                    },
                    onAuthenticated: { _ in
                        // Flow B / Flow D: Sign-In → History
                        preferences.onboardingCompleted = true
                    }
                )
            }
        }
        .preferredColorScheme(colorScheme)
    }
}
