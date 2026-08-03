//
//  FloatingPillView.swift
//  Echo
//
//  Draggable floating microphone pill — the iOS equivalent of Android's
//  PillOverlayService / PillWindowManager / PillController.
//
//  Feature map vs Android:
//  ┌──────────────────────────────────────────────┬──────────────┬───────────┐
//  │ Feature                                      │ Android      │ iOS       │
//  ├──────────────────────────────────────────────┼──────────────┼───────────┤
//  │ Draggable within Echo                        │ ✅           │ ✅        │
//  │ Edge-snapping on release                     │ ✅           │ ✅        │
//  │ Position persisted across launches           │ ✅           │ ✅        │
//  │ Idle opacity (35%) when no keyboard/recording│ ✅           │ ✅        │
//  │ Full opacity when keyboard visible           │ ✅           │ ✅        │
//  │ Live recording state on pill                 │ ✅           │ ✅        │
//  │ Text injection into focused in-app field     │ ✅           │ ✅        │
//  │ Draw over OTHER apps (SYSTEM_ALERT_WINDOW)   │ ✅           │ ❌ (iOS)  │
//  │ Inject text into OTHER apps (a11y service)   │ ✅           │ ❌ (iOS)  │
//  └──────────────────────────────────────────────┴──────────────┴───────────┘
//
//  The overlay and injection protocols are isolated so a future entitlement
//  (e.g. keyboard extension) can provide cross-app injection without changing
//  any UI code.
//

import SwiftUI
import EchoCore

// MARK: - Color tokens

private extension Color {
    static let pillPrimary        = Color(red: 0.604, green: 0.659, blue: 1.0)  // #9AA8FF
    static let pillPrimaryVariant = Color(red: 0.486, green: 0.549, blue: 1.0)  // #7C8CFF
}

// MARK: - FloatingPillView

struct FloatingPillView: View {

    // MARK: - Manager (reference type — mutates recording session)

    let manager: FloatingPillManager

    // MARK: - Callbacks to HomeView

    let onTranscriptReady: (Transcription) -> Void
    /// Called with the InsertionResult after every successful transcription so
    /// HomeView can show the clipboard toast when result == .copiedToClipboard.
    let onInsertionResult: (InsertionResult) -> Void
    let onError: () -> Void
    let startRecording: () -> Void

    // MARK: - Dependencies for transcript store lookup

    @Environment(\.transcriptionStore) private var transcriptionStore
    @Environment(Preferences.self)     private var preferences

    // MARK: - Drag / position state

    /// Current position of the pill's centre.
    @State private var position: CGPoint = .zero
    /// Accumulated drag offset during an active gesture.
    @State private var dragOffset: CGSize = .zero
    /// True while the user is actively dragging.
    @State private var isDragging: Bool = false

    // MARK: - Screen geometry (read once in onAppear, updated on rotation)

    @State private var screenSize: CGSize = UIScreen.main.bounds.size

    // MARK: - Pill dimensions

    private let pillW: CGFloat = 60
    private let pillH: CGFloat = 60
    private let edgeMargin: CGFloat = 16   // minimum clearance from screen edge

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            pillContent
                .frame(width: pillW, height: pillH)
                // Position is the centre of the pill in the GeometryReader's
                // coordinate space, offset by the live drag gesture.
                .position(
                    x: clampedX(position.x + dragOffset.width,  geo: geo),
                    y: clampedY(position.y + dragOffset.height, geo: geo)
                )
                // Opacity: fully opaque when recording or keyboard visible;
                // fades to idleOpacity otherwise. Keyboard detection from
                // manager.keyboardObserver drives this in real-time.
                .opacity(manager.isActive || isDragging ? 1.0 : FloatingPillManager.idleOpacity)
                .animation(
                    manager.keyboardObserver.swiftUIAnimation,
                    value: manager.keyboardObserver.isVisible
                )
                .animation(.spring(duration: 0.2), value: isDragging)
                .gesture(dragGesture(geo: geo))
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
                    // Re-clamp position when the screen rotates.
                    position = CGPoint(
                        x: clampedX(position.x, geo: geo),
                        y: clampedY(position.y, geo: geo)
                    )
                }
        }
        // Allow the pill to float anywhere in the safe area.
        .ignoresSafeArea(.keyboard)
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

    // MARK: - Idle mic button

    private var idleMicButton: some View {
        Button { startRecording() } label: {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.pillPrimary, .pillPrimaryVariant],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: pillW, height: pillH)
                    .shadow(color: Color.pillPrimary.opacity(isDragging ? 0.15 : 0.45),
                            radius: isDragging ? 4 : 12, x: 0, y: isDragging ? 2 : 6)

                Image(systemName: "mic.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color(red: 0.04, green: 0.06, blue: 0.18))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start recording")
        .accessibilityHint("Tap to record, drag to move")
    }

    // MARK: - Recording pill body

    @ViewBuilder
    private func recordingPillBody(rvm: RecordingViewModel) -> some View {
        ZStack {
            // Background capsule — matches RecordingPillView gradient
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.pillPrimary, .pillPrimaryVariant],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.pillPrimary.opacity(0.45), radius: 10, x: 0, y: 5)

            if rvm.isTranscribing {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.9)
            } else {
                // Stop icon while recording, mic while ready
                Image(systemName: rvm.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: pillW, height: pillH)
        .overlay(
            // Pulsing ring while recording
            Circle()
                .strokeBorder(Color.white.opacity(pulseOpacity(for: rvm)), lineWidth: 2)
                .scaleEffect(pulseScale(for: rvm))
                .animation(
                    rvm.isRecording
                        ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                        : .default,
                    value: rvm.isRecording
                )
        )
        .onTapGesture {
            if rvm.isRecording {
                Task { await manager.stopRecording() }
            }
        }
        .accessibilityLabel(rvm.isRecording ? "Stop recording" : "Transcribing…")
    }

    @State private var _pulseOpacity: Double = 0.35
    @State private var _pulseScale:   CGFloat = 1.0

    private func pulseOpacity(for rvm: RecordingViewModel) -> Double { _pulseOpacity }
    private func pulseScale(for rvm: RecordingViewModel)   -> CGFloat { _pulseScale }

    // MARK: - Drag gesture

    private func dragGesture(geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                isDragging = true
                dragOffset = value.translation
            }
            .onEnded { value in
                isDragging = false
                // Free positioning: keep exactly where the user dropped it.
                // Clamp only to the safe-area boundary so the pill is never
                // partially off-screen.  No edge-snapping is applied.
                let dropped = CGPoint(
                    x: position.x + value.translation.width,
                    y: position.y + value.translation.height
                )
                let clamped = CGPoint(
                    x: clampedX(dropped.x, geo: geo),
                    y: clampedY(dropped.y, geo: geo)
                )
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    position = clamped
                    dragOffset = .zero
                }
                // Persist the final position so it survives app restarts.
                savePosition(clamped)
            }
    }

    // MARK: - No edge-snapping (removed per product requirement)
    //
    // Edge-snapping root cause: the previous implementation always called
    // `snapToEdge(_:geo:)` on drag-end, which forcibly moved the pill to
    // either the left or right screen edge regardless of where the user
    // released it.  That function has been removed.  Drag-end now clamps
    // the pill within the safe area and persists the exact dropped position.

    // MARK: - Clamping helpers

    private func safeArea(geo: GeometryProxy) -> CGRect {
        CGRect(
            x: geo.safeAreaInsets.leading,
            y: geo.safeAreaInsets.top,
            width:  geo.size.width  - geo.safeAreaInsets.leading - geo.safeAreaInsets.trailing,
            height: geo.size.height - geo.safeAreaInsets.top     - geo.safeAreaInsets.bottom
        )
    }

    private func clampedX(_ x: CGFloat, geo: GeometryProxy) -> CGFloat {
        let half = pillW / 2
        let minX = geo.safeAreaInsets.leading  + half + edgeMargin
        let maxX = geo.size.width - geo.safeAreaInsets.trailing - half - edgeMargin
        return max(minX, min(maxX, x))
    }

    private func clampedY(_ y: CGFloat, geo: GeometryProxy) -> CGFloat {
        let half = pillH / 2
        // Keep pill above the keyboard when visible
        let keyboardTop = keyboardObserverTop(geo: geo)
        let minY = geo.safeAreaInsets.top    + half + edgeMargin
        let maxY = keyboardTop               - half - edgeMargin
        return max(minY, min(maxY, y))
    }

    private func keyboardObserverTop(geo: GeometryProxy) -> CGFloat {
        // If keyboard is showing, its top edge is (screen height - keyboard height).
        // We keep the pill above it.
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
            // Default: bottom-right corner snapped to right edge
            let safe = safeArea(geo: geo)
            position = CGPoint(
                x: safe.maxX - pillW / 2 - edgeMargin,
                y: safe.maxY - pillH - 48
            )
        } else {
            position = CGPoint(
                x: clampedX(CGFloat(px), geo: geo),
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
            // Fetch the persisted Transcription from the store.
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

            // insertTranscript: inject into focused field OR copy to clipboard.
            let (toShow, result) = manager.handleTranscriptionComplete(
                transcription,
                injectionEnabled: preferences.promptTextInjectionEnabled
            )

            // Report the insertion result so HomeView can show the clipboard toast.
            if let result {
                onInsertionResult(result)
            }
            // Show the detail sheet only when text was not consumed by injection.
            if let toShow {
                onTranscriptReady(toShow)
            }
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
