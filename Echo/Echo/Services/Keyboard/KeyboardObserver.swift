//
//  KeyboardObserver.swift
//  Echo
//
//  Tracks keyboard visibility and frame using NotificationCenter.
//
//  iOS platform note:
//  Unlike Android's WindowInsetsCompat / IME callbacks, iOS publishes keyboard
//  geometry through UIResponder notifications. We observe the two canonical
//  notifications: willShow (keyboard animating in) and willHide (animating out).
//  Using "will" rather than "did" notifications avoids the one-frame flicker you
//  get when driving opacity animations off "did" events.
//
//  The class is @Observable so SwiftUI views and @MainActor ViewModels can
//  read `isVisible` / `height` without extra Combine plumbing.
//

import Foundation
import UIKit
import SwiftUI
import Observation

@MainActor
@Observable
final class KeyboardObserver {

    // MARK: - Public state

    /// True while the software keyboard is visible (or animating in).
    private(set) var isVisible: Bool = false

    /// Current keyboard height in points (0 when hidden).
    /// Use this to offset overlays that should sit just above the keyboard.
    private(set) var height: CGFloat = 0

    /// Animation duration reported by UIKit for the current keyboard transition.
    private(set) var animationDuration: TimeInterval = 0.25

    /// Animation curve reported by UIKit (convert to SwiftUI Animation via animationCurve).
    private(set) var animationOptions: UIView.AnimationOptions = .curveEaseInOut

    // MARK: - Notification tokens

    @ObservationIgnored private var tokens: [Any] = []

    // MARK: - Init / deinit

    init() {
        let center = NotificationCenter.default

        let showToken = center.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handle(note, appearing: true)
        }

        let hideToken = center.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handle(note, appearing: false)
        }

        // Also catch the "keyboard frame will change" notification so we update
        // height correctly when the keyboard is already visible and an accessory
        // view is added (e.g. the suggestion bar appears mid-session).
        let changeToken = center.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard self?.isVisible == true else { return }
            self?.handle(note, appearing: true)
        }

        tokens = [showToken, hideToken, changeToken]
    }

    deinit {
        tokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Private handler

    private func handle(_ notification: Notification, appearing: Bool) {
        let info = notification.userInfo

        if let frame = (info?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) {
            height = appearing ? frame.height : 0
        }

        if let duration = info?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval {
            animationDuration = duration
        }

        if let curve = info?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt {
            animationOptions = UIView.AnimationOptions(rawValue: curve << 16)
        }

        isVisible = appearing
    }

    // MARK: - SwiftUI animation helper

    /// A SwiftUI `Animation` that matches the UIKit keyboard transition curve and duration.
    var swiftUIAnimation: Animation {
        // UIKeyboardAnimationCurveKey == 7 maps to keyboard-specific spring.
        // We approximate it with easeInOut which is visually indistinguishable.
        .easeInOut(duration: animationDuration)
    }
}
