//
//  RewriteBottomSheet.swift
//  Echo
//
//  Native SwiftUI AI Rewrite Engine sheet.
//
//  Two tabs:
//    • Presets  — named template cards INCLUDING "Translate" (which opens a
//                 language picker before generating a translated version).
//    • Custom   — free-form instruction field.
//
//  The output language is a global selector in the sheet header and applies
//  to every rewrite mode: presets, custom prompts, and translations.
//

import SwiftUI
import EchoCore

// MARK: - SupportedRewriteLanguage
//
// Single extensible source of truth for the languages offered by both the
// Translate preset picker and the global output-language menu.
// Add a new case here and it appears in both places automatically.

enum SupportedRewriteLanguage: String, CaseIterable, Identifiable {
    case english    = "English"
    case hindi      = "Hindi"
    case kannada    = "Kannada"
    case malayalam  = "Malayalam"
    case tamil      = "Tamil"
    case telugu     = "Telugu"
    case marathi    = "Marathi"
    case gujarati   = "Gujarati"
    case punjabi    = "Punjabi"
    case bengali    = "Bengali"
    case urdu       = "Urdu"
    case spanish    = "Spanish"
    case french     = "French"
    case german     = "German"
    case italian    = "Italian"
    case portuguese = "Portuguese"
    case japanese   = "Japanese"
    case korean     = "Korean"
    case chinese    = "Chinese (Simplified)"

    var id: String { rawValue }

    /// Display name shown in menus/pickers.
    var displayName: String { rawValue }

    /// Resolves a stored preference string back to a case (defaults to English).
    static func from(_ raw: String) -> SupportedRewriteLanguage {
        SupportedRewriteLanguage(rawValue: raw) ?? .english
    }
}

// MARK: - RewriteBottomSheet

struct RewriteBottomSheet: View {

    // ── Inputs / callbacks ─────────────────────────────────────────────────────
    let templates: [PromptTemplate]
    let customPromptText: String
    let onCustomPromptChanged: (String) -> Void
    /// Called for every preset (including Translate). Carries template ID and
    /// the currently selected output language.
    let onPresetSelected: (_ templateId: String, _ outputLanguage: String) -> Void
    /// Custom submit — carries the instruction text and the chosen output language.
    let onCustomPromptSubmit: (_ instruction: String, _ outputLanguage: String) -> Void
    let onDismiss: () -> Void

    /// The initial output language to show — set by the caller from
    /// TranscriptViewModel.selectedOutputLanguage (which is already seeded
    /// from the transcript's detectedLanguage).
    let initialOutputLanguage: String

    /// Called whenever the user changes the language in the sheet so the
    /// caller can persist it back to the view model + Preferences.
    let onOutputLanguageChanged: (String) -> Void

    // ── Environment ─────────────────────────────────────────────────────────────
    @Environment(Preferences.self) private var preferences

    // ── Local state ───────────────────────────────────────────────────────────
    @State private var selectedTab = 0
    /// Global output language for the entire AI Rewrite Engine.
    /// Initialised from `initialOutputLanguage` on appear.
    @State private var outputLanguage: SupportedRewriteLanguage = .english

    private let tabs = ["Presets", "Custom"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ── Header: title + global language selector ──────────────────
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.accentColor)
                    Text("AI Rewrite Engine")
                        .font(.headline.bold())

                    Spacer()

                    // Global output-language menu
                    Menu {
                        ForEach(SupportedRewriteLanguage.allCases) { lang in
                            Button {
                                outputLanguage = lang
                                preferences.rewriteOutputLanguage = lang.rawValue
                                onOutputLanguageChanged(lang.rawValue)
                            } label: {
                                if lang == outputLanguage {
                                    Label(lang.displayName, systemImage: "checkmark")
                                } else {
                                    Text(lang.displayName)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                                .font(.subheadline)
                            Text(outputLanguage.displayName)
                                .font(.subheadline)
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.10), in: Capsule())
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                // ── Tab bar ───────────────────────────────────────────────────
                Picker("", selection: $selectedTab) {
                    ForEach(tabs.indices, id: \.self) { i in
                        Text(tabs[i]).tag(i)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 12)

                Divider().padding(.top, 8)

                // ── Content ───────────────────────────────────────────────────
                Group {
                    switch selectedTab {
                    case 0: presetsTab
                    default: customPromptTab
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDismiss() }
                        .font(.body.weight(.medium))
                }
            }
        }
        .onAppear {
            // Seed from the caller's current selection (detectedLanguage-seeded value).
            // This is the single source of truth — Preferences is only a persistence
            // side-effect, not the primary source here.
            outputLanguage = SupportedRewriteLanguage.from(initialOutputLanguage)
        }
    }

    // MARK: - Presets tab

    private var presetsTab: some View {
        let sorted = templates.sorted { lhs, rhs in
            PromptTemplateRepository.defaults
                .firstIndex(where: { $0.id == lhs.id }) ?? 99
            < PromptTemplateRepository.defaults
                .firstIndex(where: { $0.id == rhs.id }) ?? 99
        }
        return ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(sorted, id: \.id) { template in
                    TemplateCard(template: template) {
                        // All presets — including Translate — use the global
                        // output language. No separate language picker needed.
                        onPresetSelected(template.id, outputLanguage.rawValue)
                        onDismiss()
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Custom prompt tab

    private var customPromptTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                Text("Custom Prompt")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField(
                    "e.g. Rewrite as a formal legal summary...",
                    text: Binding(
                        get: { customPromptText },
                        set: { onCustomPromptChanged($0) }
                    ),
                    axis: .vertical
                )
                .lineLimit(4...8)
                .textFieldStyle(.roundedBorder)

                HStack {
                    Spacer()
                    Text("\(customPromptText.count) / 500")
                        .font(.caption)
                        .foregroundStyle(customPromptText.count > 500 ? .red : .secondary)
                }

                if !customPromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Prompt Preview")
                            .font(.caption.bold())
                            .foregroundStyle(Color.accentColor)
                        Text("\"\(customPromptText.trimmingCharacters(in: .whitespacesAndNewlines))\" → \(outputLanguage.displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }

                Button {
                    onCustomPromptSubmit(customPromptText, outputLanguage.rawValue)
                    onDismiss()
                } label: {
                    Label("Generate Rewrite", systemImage: "paperplane.fill")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(
                            Color.accentColor.opacity(
                                customPromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || customPromptText.count > 500 ? 0.4 : 1.0
                            ),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                }
                .disabled(
                    customPromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || customPromptText.count > 500
                )
            }
            .padding()
            .padding(.bottom, 8)
        }
    }
}

// MARK: - TemplateCard

private struct TemplateCard: View {
    let template: PromptTemplate
    let onTap: () -> Void

    private var icon: String {
        switch template.id {
        case "professional":   return "briefcase"
        case "summary":        return "doc.text"
        case "meeting_notes":  return "note.text"
        case "bullet_points":  return "list.bullet"
        case "email":          return "envelope"
        case "action_items":   return "checklist"
        case "translate":      return "globe"
        default:               return "pencil"
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(template.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(template.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
