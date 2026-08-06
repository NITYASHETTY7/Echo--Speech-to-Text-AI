//
//  HomeView.swift
//  Echo
//
//  NavigationStack root.
//
//  Recording UX:
//  ─────────────────────────────────────────────────────────────────────────────
//  When Floating Pill is ENABLED (preferences.floatingPillEnabled == true):
//    • FloatingPillView is hosted directly in the ZStack over the history list.
//    • It is draggable, position-persisted, edge-snapping, keyboard-aware.
//    • Idle opacity ≈ 35%; full opacity when recording or keyboard visible.
//    • FloatingPillManager owns the RecordingViewModel lifecycle.
//
//  When Floating Pill is DISABLED:
//    • A static FAB (bottom-right) is shown instead.
//    • Tapping the FAB starts recording immediately; the FAB morphs into
//      RecordingPillView (the inline capsule from the previous implementation).
//
//  Both paths converge at onTranscriptReady → show TranscriptDetailSheet.
//  ─────────────────────────────────────────────────────────────────────────────

import SwiftUI
import EchoCore

// MARK: - Color tokens

private extension Color {
    static let echoPrimary          = Color(red: 0.604, green: 0.659, blue: 1.0)
    static let echoPrimaryVariant   = Color(red: 0.486, green: 0.549, blue: 1.0)
    static let echoOnSurfaceVariant = Color(red: 0.620, green: 0.620, blue: 0.682)
}

// MARK: - HomeView

struct HomeView: View {

    // MARK: - Environment

    @Environment(\.keychainStore)       private var keychainStore
    @Environment(\.transcriptionStore) private var transcriptionStore
    @Environment(Preferences.self)      private var preferences
    @Environment(ProviderSettings.self) private var providerSettings
    @Environment(AuthViewModel.self)    private var authViewModel
    @Environment(\.aiService)          private var aiService

    // MARK: - ViewModels

    @State private var viewModel: HomeViewModel?

    // MARK: - Navigation

    @State private var navigationPath       = NavigationPath()
    @State private var selectedTranscription: Transcription?

    // MARK: - Floating pill (enabled path)

    @State private var pillManager = FloatingPillManager()

    // MARK: - Static FAB recording state (disabled-pill path)

    @State private var staticRecordingViewModel: RecordingViewModel?

    /// True when the current static-FAB recording was started by press-and-hold.
    /// When the finger lifts, recording stops automatically without a second tap.
    @State private var isFABHoldMode: Bool = false
    /// Timestamp of when the current FAB touch began; used to detect quick taps.
    @State private var fabTouchStart: Date? = nil

    // MARK: - Clipboard toast

    /// Set to true after a transcription is copied to the clipboard instead of
    /// being injected into a focused text field. Drives the lightweight toast
    /// banner shown via .clipboardToast(isPresented:).
    @State private var showClipboardToast = false

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if let vm = viewModel {
                    mainContent(vm: vm)
                } else {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationDestination(for: NavigationDestination.self) { destination in
                destinationView(for: destination)
            }
            .sheet(item: $selectedTranscription) { transcription in
                transcriptDetailSheet(transcription: transcription)
            }
        }
        // Clipboard toast — shown only when insertion falls back to the clipboard.
        // Appears at the top of the screen, auto-dismisses after 2.5 s, never
        // blocks interaction. Only triggered on successful transcription — never
        // on cancel or error (those paths don't call handleTranscriptReady).
        .clipboardToast(isPresented: $showClipboardToast)
        .task { setupViewModel() }
        .onAppear { viewModel?.refreshProviderState() }
        // ── Reactive session/history sync ──────────────────────────────────────
        // Observe the single source of truth for auth state — the AuthViewModel's
        // @Observable `currentUser`.  This is more reliable than imperative
        // sign-out/sign-in callbacks tied to view lifecycle, which could race with
        // the RootView swap and leave stale cards visible.
        //
        //  • uid becomes nil (sign-out)   → clear the in-memory list immediately,
        //                                    so the History screen shows its empty
        //                                    state before RootView navigates away.
        //  • uid changes to a new value   → reload filtered strictly by that UID,
        //                                    so only the new user's records appear.
        //
        // The initial load for a freshly-signed-in user still happens in
        // setupViewModel() (onChange does not fire for the initial value).
        .onChange(of: authViewModel.currentUser?.uid) { _, newUid in
            if let uid = newUid {
                viewModel?.loadLatest(ownerUid: uid)
            } else {
                viewModel?.clearHistory()
            }
        }
    }

    // MARK: - Main content

    @ViewBuilder
    private func mainContent(vm: HomeViewModel) -> some View {
        ZStack {
            // ── Scrollable history ──────────────────────────────────────────
            ScrollView {
                LazyVStack(spacing: 0) {
                    // ── Screen header (icon + title/subtitle + settings gear) ──
                    // Built as a regular SwiftUI row inside the scroll content so
                    // it is truly leading-aligned.  Using ToolbarItem (in any
                    // placement) delegates layout to UIKit's navigation bar, which
                    // measures and centres toolbar items regardless of Spacer or
                    // HStack modifiers — that is why previous attempts remained
                    // visually centred.  An in-content row has no such constraint.
                    screenHeader
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    bannerSection(vm: vm)
                    historySection(vm: vm)
                }
            }
            .background(Color(.systemBackground))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 96)
            }

            // ── Recording control ───────────────────────────────────────────
            if preferences.floatingPillEnabled {
                FloatingPillView(
                    manager: pillManager,
                    onTranscriptReady: { transcription in
                        handleTranscriptReady(transcription)
                    },
                    onInsertionResult: { result in
                        if result == .copiedToClipboard {
                            withAnimation { showClipboardToast = true }
                        }
                    },
                    onError: {
                        pillManager.finishSession()
                        viewModel?.loadLatest(ownerUid: authViewModel.currentUser?.uid)
                    },
                    startRecording: {
                        startPillRecordingSession()
                    }
                )
            } else {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        staticRecordingControl
                            .padding(.trailing, 24)
                            .safeAreaPadding(.bottom, 16)
                    }
                }
            }
        }
        // Hide the system navigation bar entirely — the header is now rendered
        // inside the content area where SwiftUI's own layout engine controls it.
        .navigationBarHidden(true)
        .onAppear { vm.loadLatest(ownerUid: authViewModel.currentUser?.uid) }
    }

    // MARK: - In-content screen header
    //
    // Full-width HStack: [icon + title/subtitle]  →  Spacer  →  [settings gear]
    // Padding is applied by the call site (16 pt leading/trailing).
    // This is structurally identical to the Android ScreenHeader composable.

    private var screenHeader: some View {
        HStack(alignment: .center, spacing: 0) {
            // ── Icon + title/subtitle ─────────────────────────────────────────
            HStack(spacing: 10) {
                ZStack {
                    LinearGradient(
                        colors: [.echoPrimary, .echoPrimaryVariant],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .frame(width: 34, height: 34)

                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("History")
                        .font(.headline)
                        .foregroundStyle(Color(.label))
                    Text("Recent transcriptions")
                        .font(.caption2)
                        .foregroundStyle(Color.echoOnSurfaceVariant)
                }
            }

            Spacer()

            // ── Settings gear ─────────────────────────────────────────────────
            Button {
                navigationPath.append(NavigationDestination.settings)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.echoOnSurfaceVariant)
            }
            .accessibilityLabel("Settings")
        }
    }

    // MARK: - Static FAB / inline pill (floating pill DISABLED)

    @ViewBuilder
    private var staticRecordingControl: some View {
        if let rvm = staticRecordingViewModel {
            RecordingPillView(viewModel: rvm) {
                Task { await rvm.stopRecording() }
            } onCancel: {
                rvm.cancelRecording()
                finishStaticSession()
            } onTranscriptReady: { transcription in
                finishStaticSession()
                handleTranscriptReady(transcription)
            } onError: {
                finishStaticSession()
            }
            .transition(AnyTransition.scale(scale: 0.85).combined(with: .opacity))
        } else {
            idleFAB
                .transition(AnyTransition.scale(scale: 0.85).combined(with: .opacity))
        }
    }

    private var idleFAB: some View {
        // Supports two interaction modes that coexist without conflicting:
        //
        //  1. Tap mode (existing):   quick tap (< 250 ms, < 10 pt movement)
        //                            → startStaticRecordingSession()
        //                            → RecordingPillView shown; user taps Stop.
        //
        //  2. Hold mode (new):       touch-down → startStaticRecordingSession() immediately.
        //                            touch-up   → stopRecording() automatically.
        //                            No second tap required.
        //
        // DragGesture(minimumDistance: 0) is used because it fires .onChanged on
        // the very first touch contact and .onEnded on lift, giving reliable
        // touch-down / touch-up events without LongPressGesture timing quirks.
        //
        // The static FAB and the RecordingPillView are separate views in the ZStack,
        // but the gesture is on the idleFAB view which is only visible when
        // staticRecordingViewModel == nil.  onEnded fires even if the view is
        // removed mid-gesture (SwiftUI cancels the gesture and delivers onEnded).

        let fabVisual = ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [.echoPrimary, .echoPrimaryVariant],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 64, height: 64)
                .shadow(color: Color.echoPrimary.opacity(0.4), radius: 12, x: 0, y: 6)
            EchoIllustrationImage(size: 48)
        }

        let touchGesture = DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !isFABHoldMode, staticRecordingViewModel == nil else { return }
                isFABHoldMode  = true
                fabTouchStart  = Date()
                startStaticRecordingSession()
            }
            .onEnded { value in
                guard isFABHoldMode else { return }

                let elapsed    = fabTouchStart.map { Date().timeIntervalSince($0) } ?? 1
                let moved      = abs(value.translation.width) > 10
                              || abs(value.translation.height) > 10
                let isQuickTap = elapsed < 0.25 && !moved

                isFABHoldMode  = false
                fabTouchStart  = nil

                if isQuickTap {
                    // Quick tap: leave recording running, user taps Stop.
                } else {
                    // Hold released — stop as soon as the recorder is recording.
                    // startStaticRecordingSession() fires Task { await rvm.startRecording() }
                    // so the rvm may not be .isRecording yet when onEnded fires.
                    // We capture rvm here; the Task below waits for it to start.
                    guard let rvm = staticRecordingViewModel else { return }
                    Task {
                        // Wait up to 3 s for the recorder to reach .recording.
                        let deadline = Date().addingTimeInterval(3.0)
                        while !rvm.isRecording && Date() < deadline {
                            try? await Task.sleep(nanoseconds: 30_000_000) // 30 ms
                        }
                        if rvm.isRecording {
                            await rvm.stopRecording()
                        }
                    }
                }
            }

        return fabVisual
            .gesture(touchGesture)
            .accessibilityLabel("Start recording")
            .accessibilityHint("Tap to toggle recording, or press and hold to record while held")
    }

    // MARK: - Floating pill recording session

    private func startPillRecordingSession() {
        guard let store    = transcriptionStore,
              let keychain = keychainStore else { return }
        pillManager.startRecording(
            store: store,
            keychainStore: keychain,
            providerSettings: providerSettings,
            preferences: preferences,
            aiService: aiService,
            ownerUid: authViewModel.currentUser?.uid ?? "local"
        )
    }

    // MARK: - Static FAB recording session

    private func startStaticRecordingSession() {
        guard staticRecordingViewModel == nil,
              let store    = transcriptionStore,
              let keychain = keychainStore else { return }

        let recorder = AudioRecorder()
        let factory  = ProviderFactory(keychainStore: keychain, providerSettings: providerSettings)
        let pipeline = DefaultTranscriptionPipeline(providerFactory: factory)
        let captured = authViewModel
        let coordinator = TranscriptionCoordinator(
            pipeline: pipeline,
            preferences: preferences,
            providerSettings: providerSettings,
            store: store,
            ownerUidProvider: { captured.currentUser?.uid ?? "local" },
            aiService: aiService
        )
        let rvm = RecordingViewModel(recorder: recorder, coordinator: coordinator)
        staticRecordingViewModel = rvm
        Task { await rvm.startRecording() }
    }

    private func finishStaticSession() {
        withAnimation(.spring(duration: 0.25)) {
            staticRecordingViewModel = nil
        }
        viewModel?.loadLatest(ownerUid: authViewModel.currentUser?.uid)
        viewModel?.refreshProviderState()
    }

    // MARK: - Shared transcript handler

    private func handleTranscriptReady(_ transcription: Transcription) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            selectedTranscription = transcription
            viewModel?.loadLatest(ownerUid: authViewModel.currentUser?.uid)
        }
    }

    // MARK: - Banners

    @ViewBuilder
    private func bannerSection(vm: HomeViewModel) -> some View {
        VStack(spacing: 0) {
            if !vm.isProviderConfigured {
                ProviderNotConfiguredBanner {
                    navigationPath.append(NavigationDestination.settings)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            MicPermissionBannerView()
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
        }
        .animation(.easeInOut(duration: 0.3), value: vm.isProviderConfigured)
    }

    // MARK: - History list (date-grouped)

    @ViewBuilder
    private func historySection(vm: HomeViewModel) -> some View {
        let groups = vm.groupedTranscriptions
        if groups.isEmpty {
            historyEmptyState
        } else {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(groups) { group in
                    Section {
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { index, t in
                            AnimatedTranscriptCardRow(transcription: t, index: index) {
                                selectedTranscription = t
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 10)
                        }
                    } header: {
                        HStack {
                            Text(group.label)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color(.systemBackground))
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Empty state

    private var historyEmptyState: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 60)
            ZStack {
                RadialGradient(
                    colors: [Color.echoPrimary.opacity(0.20), Color.echoPrimaryVariant.opacity(0.08)],
                    center: .center, startRadius: 0, endRadius: 48
                )
                .clipShape(Circle())
                .frame(width: 96, height: 96)
                .overlay(
                    Circle().strokeBorder(
                        LinearGradient(
                            colors: [Color.echoPrimary.opacity(0.4), Color.echoPrimaryVariant.opacity(0.2)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                )
                Image(systemName: "mic")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.echoPrimary)
            }
            Spacer().frame(height: 4)
            Text("No transcriptions yet")
                .font(.title3).fontWeight(.medium).foregroundStyle(Color(.label))
            Text("Start dictating to see your history.")
                .font(.subheadline)
                .foregroundStyle(Color.echoOnSurfaceVariant)
                .opacity(0.7).multilineTextAlignment(.center)
            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
    }

    // MARK: - Transcript detail sheet

    @ViewBuilder
    private func transcriptDetailSheet(transcription: Transcription) -> some View {
        if let store = transcriptionStore {
            let tvm = TranscriptViewModel(transcription: transcription, store: store, aiService: aiService, preferences: preferences)
            TranscriptDetailSheet(viewModel: tvm) {
                selectedTranscription = nil
                viewModel?.loadLatest(ownerUid: authViewModel.currentUser?.uid)
            }
        }
    }

    // MARK: - Navigation destinations

    @ViewBuilder
    private func destinationView(for destination: NavigationDestination) -> some View {
        switch destination {
        case .settings:
            SettingsView()
        case .transcript(let t):
            if let store = transcriptionStore {
                let tvm = TranscriptViewModel(transcription: t, store: store, aiService: aiService, preferences: preferences)
                TranscriptView(viewModel: tvm)
            }
        }
    }

    // MARK: - ViewModel setup

    private func setupViewModel() {
        guard viewModel == nil,
              let store    = transcriptionStore,
              let keychain = keychainStore else { return }
        let vm = HomeViewModel(store: store, providerSettings: providerSettings, keychainStore: keychain)
        viewModel = vm

        // Initial load, filtered by the current user (nil = guest mode).
        // Subsequent auth-state changes are handled reactively by the
        // .onChange(of: authViewModel.currentUser?.uid) observer on the body —
        // no fragile imperative sign-in/sign-out callbacks are needed.
        vm.loadLatest(ownerUid: authViewModel.currentUser?.uid)
    }
}

// MARK: - ProviderNotConfiguredBanner

struct ProviderNotConfiguredBanner: View {
    let onSetUp: () -> Void
    var body: some View {
        HStack {
            Text("Configure your AI speech provider to start transcribing")
                .font(.caption).foregroundStyle(Color(.label).opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Set Up", action: onSetUp)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.echoPrimary)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color.echoPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.echoPrimary.opacity(0.25), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Provider not configured.")
        .accessibilityHint("Tap Set Up to configure.")
    }
}

// MARK: - MicPermissionBannerView

private struct MicPermissionBannerView: View {
    @Environment(\.openURL)       private var openURL
    @Environment(\.scenePhase)    private var scenePhase
    @State private var isDenied = false
    var body: some View {
        Group {
            if isDenied {
                HStack {
                    Text("Microphone permission required for recording")
                        .font(.caption).foregroundStyle(Color(.label).opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Allow") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        openURL(url)
                    }
                    .font(.subheadline.weight(.medium)).foregroundStyle(Color(.systemRed))
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Color(.systemRed).opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(.systemRed).opacity(0.3), lineWidth: 0.5))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isDenied)
        .onAppear { checkPermission() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { checkPermission() } }
    }
    private func checkPermission() {
        if #available(iOS 17.0, *) {
            isDenied = AVAudioApplication.shared.recordPermission == .denied
        } else {
            isDenied = AVAudioSession.sharedInstance().recordPermission == .denied
        }
    }
}

// MARK: - AnimatedTranscriptCardRow

private struct AnimatedTranscriptCardRow: View {
    let transcription: Transcription
    let index: Int
    let onTap: () -> Void
    @State private var appeared = false
    var body: some View {
        Button(action: onTap) {
            TranscriptCard(transcription: transcription).padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 20)
        .animation(.easeOut(duration: 0.20).delay(Double(min(index, 8)) * 0.04), value: appeared)
        .onAppear { appeared = true }
        .accessibilityLabel("Transcription")
        .accessibilityHint("Tap to open full transcript")
    }
}

// MARK: - Navigation destinations

enum NavigationDestination: Hashable {
    case settings
    case transcript(Transcription)
}

extension Transcription: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

import AVFoundation

#Preview { ContentView() }
