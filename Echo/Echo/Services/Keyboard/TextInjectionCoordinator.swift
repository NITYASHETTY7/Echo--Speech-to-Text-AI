//
//  TextInjectionCoordinator.swift
//  Echo
//
//  Single entry-point for transcript insertion. Attempts UITextInput injection
//  first; falls back to UIPasteboard when no editable responder is focused.
//
//  iOS Platform limitations vs Android:
//  ─────────────────────────────────────────────────────────────────────────────
//  Android AccessibilityService can call insertText() on any view in any app.
//  iOS CANNOT access UITextInput across process boundaries.
//  Inside Echo we walk the UIResponder chain, which gives us full cursor-level
//  control of any native UITextField / UITextView / UISearchBar.
//
//  The TextInjecting protocol is the extension point:  a future Keyboard
//  Extension process can provide its own conformer that writes through
//  UIInputViewController without changing any call site.
//  ─────────────────────────────────────────────────────────────────────────────

import UIKit

// MARK: - InsertionResult

/// Describes what happened when insertTranscript(_:) was called.
/// Callers use this to decide whether to show a toast, open a detail sheet, etc.
public enum InsertionResult: Equatable {
    /// Text was inserted at the cursor of a focused UITextInput responder.
    case injected
    /// No editable responder was active; text was copied to UIPasteboard.
    case copiedToClipboard
}

// MARK: - TextInjecting protocol

/// The single public API for inserting a finished transcript.
/// Implementations must be @MainActor-isolated because UIKit text operations
/// require the main thread.
protocol TextInjecting {

    /// Primary entry point.
    ///
    /// Behaviour (in order):
    ///  1. Locate the first-responder UITextInput inside the key window.
    ///  2. If found and editable: insert `text` at the current insertion point,
    ///     preserving any existing content and the cursor position.
    ///  3. If not found: copy `text` to UIPasteboard.general.
    ///  4. Return an `InsertionResult` so callers can react (e.g. show a toast).
    @MainActor
    @discardableResult
    func insertTranscript(_ text: String) -> InsertionResult

    /// True when a UITextInput responder is currently first-responder.
    /// Use this to query availability without side effects.
    @MainActor var canInject: Bool { get }

    // Legacy inject(_:) kept for backward compatibility.
    // New code should prefer insertTranscript(_:).
    @MainActor
    @discardableResult
    func inject(_ text: String) -> Bool
}

// MARK: - TextInjectionCoordinator

/// Concrete implementation that operates inside the Echo process.
@MainActor
final class TextInjectionCoordinator: TextInjecting {

    // MARK: - TextInjecting

    var canInject: Bool {
        activeEditableTextInput() != nil
    }

    /// Insert the transcript at the cursor of the focused text field, or copy
    /// to clipboard when no editable field is active.
    @discardableResult
    func insertTranscript(_ text: String) -> InsertionResult {
        if let input = activeEditableTextInput() {
            insertAtCursor(text, into: input)
            return .injected
        }
        // Clipboard fallback — only on successful transcription (caller's
        // responsibility to not call this on cancel / error).
        UIPasteboard.general.string = text
        return .copiedToClipboard
    }

    /// Legacy method. Delegates to insertTranscript and maps to Bool.
    @discardableResult
    func inject(_ text: String) -> Bool {
        insertTranscript(text) == .injected
    }

    // MARK: - Cursor-preserving insertion

    /// Inserts `text` at the current cursor position inside `input`.
    ///
    /// Why not just call `insertText(_:)`?
    /// `UITextInput.insertText(_:)` replaces the current *selected* range,
    /// which is the correct cursor-position-aware behaviour for commitText in
    /// Android's InputConnection.  We call it directly — the system handles
    /// undo, autocorrect etc.  We do NOT manually manipulate selectedTextRange
    /// first because UITextField/UITextView already tracks the insertion point.
    private func insertAtCursor(_ text: String, into input: UITextInput) {
        input.insertText(text)
    }

    // MARK: - Active editable UITextInput detection
    //
    // Detection is based on the UIResponder first-responder, NOT keyboard
    // visibility. The keyboard can be visible without a focused editable field
    // (e.g. a search bar that dismissed its keyboard but kept focus), and
    // conversely a field can be first-responder just before the keyboard
    // animates in.  Walking the responder chain directly is the correct approach.

    /// Returns the first-responder UITextInput only if it is currently editable.
    /// Returns nil if:
    ///  - There is no first-responder.
    ///  - The first-responder does not conform to UITextInput.
    ///  - The field is non-editable (isEditable == false on UITextView, etc.).
    private func activeEditableTextInput() -> UITextInput? {
        guard let window = keyWindow(),
              let responder = findFirstResponder(in: window),
              let textInput = responder as? UITextInput else { return nil }

        // Reject non-editable views.
        if let textView = responder as? UITextView, !textView.isEditable { return nil }

        return textInput
    }

    private func keyWindow() -> UIWindow? {
        UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
    }

    /// Depth-first search for the current first-responder in the view tree.
    private func findFirstResponder(in view: UIView) -> UIResponder? {
        if view.isFirstResponder { return view }
        for sub in view.subviews {
            if let found = findFirstResponder(in: sub) { return found }
        }
        return nil
    }
}
