//
//  FloatingPillView.swift
//  Echo
//
//  Draggable floating microphone pill — the iOS equivalent of Android's
//  PillOverlayService / PillWindowManager / PillController.
//
//  ─────────────────────────────────────────────────────────────────────────
//  Gesture architecture — single-gesture state machine
//  ─────────────────────────────────────────────────────────────────────────
//  A SINGLE `DragGesture(minimumDistance: 0)` owns the ENTIRE touch lifecycle.
//  This is the only reliable way to receive a "touch-up" event for an
//  arbitrarily long hold:
//
//    • DragGesture(minimumDistance: 0).onChanged fires immediately on touch-down
//      (translation == .zero) and on every movement.
//    • DragGesture.onEnded is GUARANTEED to fire when the finger lifts — anywhere
//      on screen, regardless of how long the finger was held or where it moved.
//
//  Why NOT LongPressGesture (the previous bug):
//    LongPressGesture is a DISCRETE recognizer.  It completes and fires onEnded
//    at `minimumDuration` (while the finger is still down) and then STOPS
//    tracking the touch.  It never reports finger-lift, and its @GestureState
//    resets at the completion point — so the release event never reached the
//    stop-recording logic and recording ran forever.
//
//  Touch disambiguation (tap vs. hold vs. drag) via a cancellable timer:
//
//    TOUCH DOWN ─┬─ move > 8pt before timer ───────────────► DRAG  (reposition)
//                │
//                ├─ still held ≥ holdDelay (timer fires) ───► HOLD  (record while held)
//                │                                            release → stop
//                │
//                └─ lifts before timer, < 8pt movement ─────► TAP   (toggle record)
//
//  • Drag never starts recording (timer is cancelled the moment drag begins).
//  • Hold starts recording when the timer fires and ALWAYS stops on release
//    (onEnded), because the single DragGesture owns the whole lifecycle.
//  • Tap toggles recording (start when idle, stop when recording).
//  ─────────────────────────────────────────────────────────────────────────

import SwiftUI
import EchoCore

// MARK: - Color tokens

private extension Color {
    static let pillPrimary        = Color(red: 0.604, green: 0.659, blue: 1.0)  // #9AA8FF
    static let pillPrimaryVariant = Color(red: 0.486, green: 0.549, blue: 1.0)  // #7C8CFF
}

// MARK: - EchoIllustrationImage

/// Renders the Echo brand illustration from the main bundle asset catalog.
/// Pure SwiftUI — no UIKit bridge — so the image lookup always resolves
/// against the correct bundle regardless of debug-dylib vs release config.
/// Shared by FloatingPillView (overlay pill) and HomeView (static FAB).
struct EchoIllustrationImage: View {
    let size: CGFloat

    var body: some View {
        Image("EchoIllustration", bundle: .main)
            .resizable()
            .renderingMode(.original)
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

// MARK: - FloatingPillView

struct FloatingPillView: View {

    // MARK: - Manager

    let manager: FloatingPillManager

    // MARK: - Callbacks to HomeView

    let onTranscriptReady: (Transcription) -> Void
    let onInsertionResult: (InsertionResult) -> Void
    let onError: () -> Void
    let startRecording: () -> Void

    // MARK: - Environment

    @Environment(\.transcriptionStore) private var transcriptionStore
    @Environment(Preferences.self)     private var preferences

    // MARK: - Position state

    @State private var position:   CGPoint = .zero
    @State private var dragOffset: CGSize  = .zero
    @State private var isDragging: Bool    = false

    // MARK: - Touch state machine

    /// The interaction the current touch has resolved into.
    private enum TouchMode { case undecided, drag, hold }

    @State private var touchMode:           TouchMode = .undecided
    @State private var touchStartTime:      Date?     = nil
    /// Cancellable timer that promotes a still touch into a hold after `holdDelay`.
    @State private var holdTask:            Task<Void, Never>? = nil
    /// Set true the moment the hold timer fires and startRecording() is called.
    /// Stays true until onEnded resets it, ensuring stopRecording() is always
    /// called on release even if recordingViewModel is not yet set (race window).
    @State private var holdStartedRecording: Bool = false

    // MARK: - Screen geometry

    @State private var screenSize: CGSize = UIScreen.main.bounds.size

    // MARK: - Tunables

    private let pillW:         CGFloat = 60
    private let pillH:         CGFloat = 60
    private let edgeMargin:    CGFloat = 16
    /// Movement (pt) beyond which a still touch becomes a drag.
    private let dragThreshold: CGFloat = 8
    /// Stillness (s) after which a held touch becomes a hold-to-record.
    private let holdDelay:     TimeInterval = 0.3

    // MARK: - Pulse

    @State private var _pulseOpacity: Double  = 0.35
    @State private var _pulseScale:   CGFloat = 1.0

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            // The gesture lives on this stable ZStack wrapper, NOT on pillContent.
            // When recording starts, pillContent swaps from idleMicButton to
            // recordingPillBody — if the gesture were on pillContent, SwiftUI
            // would destroy and recreate it mid-touch, dropping onEnded entirely
            // (the root cause of "release doesn't stop recording").
            // By keeping the gesture on this outer wrapper, which never changes
            // identity, onEnded always fires no matter what pillContent renders.
            ZStack {
                pillContent
            }
            .frame(width: pillW, height: pillH)
            .position(
                x: clampedX(position.x + dragOffset.width,  geo: geo),
                y: clampedY(position.y + dragOffset.height, geo: geo)
            )
            .opacity(manager.isActive || isDragging ? 1.0 : FloatingPillManager.idleOpacity)
            .animation(manager.keyboardObserver.swiftUIAnimation,
                       value: manager.keyboardObserver.isVisible)
            .animation(.spring(duration: 0.2), value: isDragging)
            // Gesture on the stable ZStack wrapper — survives pillContent swaps.
            .gesture(pillGesture(geo: geo))
            .onChange(of: manager.recordingViewModel?.transcriptionState) { _, state in
                handleTranscriptionState(state)
            }
            .onChange(of: manager.recordingViewModel?.recordingState) { _, state in
                handleRecordingStateChange(state)
            }
            .onAppear {
                screenSize = geo.size
                restorePosition(geo: geo)
            }
            .onChange(of: geo.size) { _, newSize in
                screenSize = newSize
                position = CGPoint(
                    x: snappedX(position.x, geo: geo),
                    y: clampedY(position.y, geo: geo)
                )
            }
            .onDisappear { cancelHoldTimer() }
        }
        .ignoresSafeArea(.keyboard)
    }

    // MARK: - Unified gesture (tap + hold + drag)

    private func pillGesture(geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                // ── Touch down (first onChanged of this touch) ───────────────
                if touchStartTime == nil {
                    touchStartTime = Date()
                    touchMode      = .undecided
                    scheduleHoldTimer()
                }

                let moved = max(abs(value.translation.width),
                                abs(value.translation.height))

                switch touchMode {
                case .undecided:
                    // Movement before the hold timer fires → this is a DRAG.
                    if moved > dragThreshold {
                        touchMode = .drag
                        cancelHoldTimer()          // drag cancels the pending hold
                        isDragging = true
                        dragOffset = value.translation
                    }
                case .drag:
                    dragOffset = value.translation
                case .hold:
                    break                          // recording; ignore movement
                }
            }
            .onEnded { value in
                // onEnded ALWAYS fires on finger-up — this is what makes
                // hold-release reliable.  Capture state, then reset.
                cancelHoldTimer()

                let moved = max(abs(value.translation.width),
                                abs(value.translation.height))
                let mode             = touchMode
                let didStartRecording = holdStartedRecording

                touchStartTime       = nil
                touchMode            = .undecided
                holdStartedRecording = false

                switch mode {
                case .drag:
                    finalizeDrag(value: value, geo: geo)

                case .hold:
                    // Release ends the hold → stop recording.
                    // Always attempt stop: even if recordingViewModel is not yet
                    // set (race window between timer firing and startRecording
                    // completing), we give the manager a chance to stop as soon
                    // as the VM exists by calling stopRecording() unconditionally.
                    Task { await manager.stopRecording() }

                case .undecided:
                    // Finger lifted before the hold timer AND without dragging.
                    if didStartRecording {
                        // The hold timer fired and startRecording() was called, but
                        // the touch ended before we ever left .undecided (race).
                        // Stop the recording that was just started.
                        Task { await manager.stopRecording() }
                    } else if moved <= dragThreshold {
                        // Clean quick tap — toggle recording.
                        handleTap()
                    }
                }
            }
    }

    // MARK: - Hold timer

    /// Schedules promotion of a still touch into hold-to-record after `holdDelay`.
    /// Cancelled if the finger drags or lifts first.
    private func scheduleHoldTimer() {
        holdTask?.cancel()
        holdTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(holdDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            // Only promote to hold if the touch is still undecided (finger down,
            // no drag started, not lifted).
            guard touchMode == .undecided else { return }
            touchMode = .hold
            // Start recording only if idle — a hold while already recording
            // simply arms the release-to-stop behaviour.
            if manager.recordingViewModel == nil {
                holdStartedRecording = true
                startRecording()
            }
        }
    }

    private func cancelHoldTimer() {
        holdTask?.cancel()
        holdTask = nil
    }

    // MARK: - Tap handling (toggle)

    private func handleTap() {
        if let rvm = manager.recordingViewModel {
            if rvm.isRecording {
                Task { await manager.stopRecording() }
            }
        } else {
            startRecording()
        }
    }

    // MARK: - Drag finalisation

    private func finalizeDrag(value: DragGesture.Value, geo: GeometryProxy) {
        isDragging = false
        let dropped = CGPoint(
            x: position.x + value.translation.width,
            y: position.y + value.translation.height
        )
        // Snap X to the nearest left/right edge; clamp Y within safe bounds.
        let snapped = CGPoint(
            x: snappedX(dropped.x, geo: geo),
            y: clampedY(dropped.y, geo: geo)
        )
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            position   = snapped
            dragOffset = .zero
        }
        savePosition(snapped)
    }

    // MARK: - Pill content

    @ViewBuilder
    private var pillContent: some View {
        if let rvm = manager.recordingViewModel {
            recordingPillBody(rvm: rvm)
        } else {
            idleMicButton
        }
    }

    private var idleMicButton: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [.pillPrimary, .pillPrimaryVariant],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: pillW, height: pillH)
                .shadow(color: Color.pillPrimary.opacity(isDragging ? 0.15 : 0.45),
                        radius: isDragging ? 4 : 12, x: 0, y: isDragging ? 2 : 6)

            // Custom Echo illustration — rendered at original colours (no tint).
            // Uses Bundle.main explicitly so the asset lookup works in both
            // debug dylib and release configurations.
            // Falls back to mic.fill if the asset is absent.
            EchoIllustrationImage(size: pillW - 16)
        }
        .accessibilityLabel("Start recording")
        .accessibilityHint("Tap to toggle, hold to record while held, drag to move")
    }

    @ViewBuilder
    private func recordingPillBody(rvm: RecordingViewModel) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [.pillPrimary, .pillPrimaryVariant],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .shadow(color: Color.pillPrimary.opacity(0.45), radius: 10, x: 0, y: 5)

            if rvm.isTranscribing {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.9)
            } else if rvm.isRecording {
                // Active recording: keep the stop-recording indicator.
                Image(systemName: "stop.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                // Idle inside the recording body — show custom illustration with
                // mic.fill fallback if the asset is unavailable.
                EchoIllustrationImage(size: pillW - 16)
            }
        }
        .frame(width: pillW, height: pillH)
        .overlay(
            Circle()
                .strokeBorder(Color.white.opacity(_pulseOpacity), lineWidth: 2)
                .scaleEffect(_pulseScale)
                .animation(
                    rvm.isRecording
                        ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                        : .default,
                    value: rvm.isRecording
                )
        )
        .accessibilityLabel(rvm.isRecording ? "Stop recording" : "Transcribing…")
    }

    // MARK: - Clamping helpers

    private func safeArea(geo: GeometryProxy) -> CGRect {
        CGRect(
            x: geo.safeAreaInsets.leading,
            y: geo.safeAreaInsets.top,
            width:  geo.size.width  - geo.safeAreaInsets.leading - geo.safeAreaInsets.trailing,
            height: geo.size.height - geo.safeAreaInsets.top     - geo.safeAreaInsets.bottom
        )
    }

    /// Returns the X coordinate snapped to either the left or the right edge,
    /// whichever the given X is closest to.  This is the horizontal component
    /// of the Android-style edge-docking behaviour: the pill can only sit on
    /// the left or the right rail — never in the middle of the screen.
    private func snappedX(_ x: CGFloat, geo: GeometryProxy) -> CGFloat {
        let half   = pillW / 2
        let leftX  = geo.safeAreaInsets.leading  + half + edgeMargin
        let rightX = geo.size.width - geo.safeAreaInsets.trailing - half - edgeMargin
        // Snap to whichever edge is nearer.
        let midScreen = geo.size.width / 2
        return x < midScreen ? leftX : rightX
    }

    /// Clamps X to [leftEdge, rightEdge] during live dragging (no snap yet).
    /// The snap only happens on drag release via `snappedX`.
    private func clampedX(_ x: CGFloat, geo: GeometryProxy) -> CGFloat {
        let half   = pillW / 2
        let leftX  = geo.safeAreaInsets.leading  + half + edgeMargin
        let rightX = geo.size.width - geo.safeAreaInsets.trailing - half - edgeMargin
        return max(leftX, min(rightX, x))
    }

    private func clampedY(_ y: CGFloat, geo: GeometryProxy) -> CGFloat {
        let half = pillH / 2
        let keyboardTop = keyboardObserverTop(geo: geo)
        let minY = geo.safeAreaInsets.top + half + edgeMargin
        let maxY = keyboardTop            - half - edgeMargin
        return max(minY, min(maxY, y))
    }

    private func keyboardObserverTop(geo: GeometryProxy) -> CGFloat {
        let kbHeight = manager.keyboardObserver.height
        if kbHeight > 0 {
            return geo.size.height - kbHeight
        }
        return geo.size.height - geo.safeAreaInsets.bottom - edgeMargin
    }

    // MARK: - Position persistence

    private func restorePosition(geo: GeometryProxy) {
        let px = preferences.floatingPillX
        let py = preferences.floatingPillY
        if px == Int.min || py == Int.min {
            // First launch: default to the right edge, near the bottom.
            let safe = safeArea(geo: geo)
            position = CGPoint(
                x: safe.maxX - pillW / 2 - edgeMargin,
                y: safe.maxY - pillH - 48
            )
        } else {
            // Snap saved X to the nearest edge in case it was stored from an
            // older build that allowed the pill to sit anywhere horizontally.
            position = CGPoint(
                x: snappedX(CGFloat(px), geo: geo),
                y: clampedY(CGFloat(py), geo: geo)
            )
        }
    }

    private func savePosition(_ point: CGPoint) {
        preferences.floatingPillX = Int(point.x)
        preferences.floatingPillY = Int(point.y)
    }

    // MARK: - Transcription state handler

    private func handleTranscriptionState(_ state: CoordinatorState?) {
        guard let state else { return }

        if case .completed(let response) = state {
            let transcription: Transcription
            if let store = transcriptionStore,
               let match = try? store.fetch(limit: 200).first(where: { $0.text == response.text }) {
                transcription = match
            } else {
                transcription = Transcription(
                    id: UUID().uuidString,
                    text: response.text,
                    timestamp: Int64(Date().timeIntervalSince1970 * 1_000),
                    model: response.model,
                    audioPath: nil,
                    userId: "local"
                )
            }

            let (toShow, result) = manager.handleTranscriptionComplete(
                transcription,
                injectionEnabled: preferences.promptTextInjectionEnabled
            )
            if let result { onInsertionResult(result) }
            if let toShow { onTranscriptReady(toShow) }
        }

        if case .failed = state {
            manager.finishSession()
            onError()
        }
    }

    private func handleRecordingStateChange(_ state: RecordingState?) {
        guard let state else { return }
        if case .failed = state { onError() }
    }
}
