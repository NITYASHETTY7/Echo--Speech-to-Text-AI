//
//  TranscriptDetailSheet.swift
//  Echo
//
//  Bottom sheet transcript detail view with full AI integration.
//  Android parity:
//  - SheetHeader → Divider → VersionSelector → Divider → content → Rewrite CTA
//  - Favorite heart is in the content header row (not buried in nav toolbar)
//  - Toolbar: close (leading) + copy/share/delete (trailing)
//

import SwiftUI
import EchoCore

struct TranscriptDetailSheet: View {

    @State var viewModel: TranscriptViewModel
    let onDismiss: (() -> Void)?

    init(viewModel: TranscriptViewModel, onDismiss: (() -> Void)? = nil) {
        self._viewModel = State(initialValue: viewModel)
        self.onDismiss = onDismiss
    }

    @Environment(\.dismiss) private var dismiss

    @State private var showRewriteSheet = false
    @State private var customPromptText = ""
    @State private var shareItem: ShareItem?
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // ── Version selector ──────────────────────────────────────
                    // Shown at the top (matches Android VersionSelector above TranscriptCard)
                    if !viewModel.versions.isEmpty {
                        VersionSelector(
                            versions: viewModel.versions,
                            activeIndex: viewModel.activeVersionIndex,
                            onSelectIndex: { viewModel.activeVersionIndex = $0 }
                        )
                        Divider()
                    }

                    // ── Header row: timestamp + duration ─────────────────────
                    // Provider name, provider icon, and favourite heart have been
                    // removed for a cleaner Android-parity header that focuses on
                    // transcript metadata only.
                    HStack(alignment: .center) {
                        Text(viewModel.relativeTimestamp)
                            .font(.caption).foregroundStyle(.tertiary)

                        Spacer()

                        if let dur = viewModel.formattedDuration {
                            Label(dur, systemImage: "timer")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    Divider()

                    // ── Active version badge ──────────────────────────────────
                    if let active = viewModel.activeVersion, active.versionType != .original {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.caption2.weight(.semibold))
                            Text(active.versionType.displayName)
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.10), in: Capsule())
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                    }

                    // ── Transcript text ───────────────────────────────────────
                    transcriptTextView
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 20)

                    Divider().padding(.horizontal, 16)

                    // ── AI Rewrite CTA ────────────────────────────────────────
                    // Full-width below transcript (matches Android "Rewrite" Button)
                    aiRewriteButton
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)

                    // ── Model chip (matches Android ModelChip) ────────────────
                    if !viewModel.modelName.isEmpty {
                        HStack {
                            Text(viewModel.modelName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color(.secondarySystemFill), in: Capsule())
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        // Safe-area-aware bottom padding so the model chip isn't
                        // hidden behind the home indicator on Face ID devices.
                        .padding(.bottom, 20)
                    }
                }
                // Ensure bottom content clears the home indicator in sheet presentations.
                .padding(.bottom, 8)
            }
            .navigationTitle("Transcription")
            .navigationBarTitleDisplayMode(.inline)
            .overlay { if viewModel.isProcessing { processingOverlay } }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { onDismiss?() ?? dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // Copy
                    Button { viewModel.copyToClipboard() } label: {
                        Image(systemName: viewModel.didCopy ? "checkmark" : "doc.on.doc")
                    }
                    .symbolEffect(.bounce, value: viewModel.didCopy)
                    .accessibilityLabel(viewModel.didCopy ? "Copied" : "Copy")

                    // Share
                    Button { shareItem = ShareItem(text: viewModel.text) } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(viewModel.text.isEmpty)
                    .accessibilityLabel("Share")

                    // Delete
                    Button(role: .destructive) { showDeleteConfirmation = true } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Delete")
                }
            }
            .sheet(item: $shareItem) { ShareSheet(text: $0.text) }
            .sheet(isPresented: $showRewriteSheet) { rewriteSheet }
            .confirmationDialog(
                "Delete this transcription?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    viewModel.delete()
                    onDismiss?() ?? dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This cannot be undone.") }
            .alert("Error", isPresented: Binding(
                get: { viewModel.processingError != nil || viewModel.deleteError != nil },
                set: { if !$0 { viewModel.dismissProcessingError(); viewModel.clearError() } }
            )) {
                Button("OK") { viewModel.dismissProcessingError(); viewModel.clearError() }
            } message: {
                Text(viewModel.processingError ?? viewModel.deleteError?.localizedDescription ?? "")
            }
        }
    }

    // MARK: - Transcript text (Markdown-aware)

    /// Renders the active transcript text using MarkdownTextView.
    /// AI-generated versions get full block + inline Markdown processing.
    /// The Original version is always displayed verbatim (plain text).
    @ViewBuilder
    private var transcriptTextView: some View {
        MarkdownTextView(
            text: viewModel.text,
            isMarkdown: viewModel.activeVersion?.versionType.isAIGenerated == true
        )
    }

    // MARK: - AI Rewrite button (matches Android "Rewrite" Button)

    private var aiRewriteButton: some View {        Button {
            showRewriteSheet = true
        } label: {
            Label("AI Rewrite", systemImage: "sparkles")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
        }
        .disabled(viewModel.isProcessing)
    }

    // MARK: - Rewrite sheet

    private var rewriteSheet: some View {
        RewriteBottomSheet(
            templates: PromptTemplateRepository.defaults,
            customPromptText: customPromptText,
            onCustomPromptChanged: { customPromptText = $0 },
            onPresetSelected: { templateId, outputLanguage in
                showRewriteSheet = false
                if templateId == "translate" {
                    viewModel.requestTranslation(targetLanguage: outputLanguage)
                } else {
                    viewModel.requestRewrite(templateId: templateId, outputLanguage: outputLanguage)
                }
            },
            onCustomPromptSubmit: { instruction, outputLanguage in
                showRewriteSheet = false
                viewModel.requestCustomRewrite(instruction: instruction, outputLanguage: outputLanguage)
                customPromptText = ""
            },
            onDismiss: { showRewriteSheet = false },
            initialOutputLanguage: viewModel.selectedOutputLanguage,
            onOutputLanguageChanged: { viewModel.selectedOutputLanguage = $0 }
        )
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Processing overlay

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().scaleEffect(1.4).tint(.white)
                Text("Processing AI rewrite…")
                    .font(.subheadline).foregroundStyle(.white)
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

// MARK: - Helpers

private struct ShareItem: Identifiable { let id = UUID(); let text: String }

private struct ShareSheet: UIViewControllerRepresentable {
    let text: String
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
