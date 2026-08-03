//
//  TranscriptView.swift
//  Echo
//
//  Full transcript view — used from History navigation.
//  Android parity:
//  - VersionSelector at top
//  - Header row with provider + timestamp + heart (content area, not toolbar)
//  - Transcript text (selectable)
//  - AI Rewrite CTA button
//  - Toolbar: close (leading) + copy/share/delete (trailing only)
//

import SwiftUI
import EchoCore

struct TranscriptView: View {

    @State var viewModel: TranscriptViewModel
    @Environment(\.dismiss) private var dismiss
    var onDismissAll: (() -> Void)?

    @State private var showDeleteConfirmation = false
    @State private var showRewriteSheet = false
    @State private var customPromptText = ""
    @State private var shareItem: ShareItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // ── Version selector ──────────────────────────────────────
                    if !viewModel.versions.isEmpty {
                        VersionSelector(
                            versions: viewModel.versions,
                            activeIndex: viewModel.activeVersionIndex,
                            onSelectIndex: { viewModel.activeVersionIndex = $0 }
                        )
                        Divider()
                    }

                    // ── Header: timestamp + duration ─────────────────────────
                    // Provider name, provider icon, and favourite heart removed
                    // for a cleaner header focused on transcript metadata only.
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
                            Image(systemName: "sparkles").font(.caption2.weight(.semibold))
                            Text(active.versionType.displayName).font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.10), in: Capsule())
                        .padding(.horizontal, 16).padding(.top, 10)
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
                    Button { showRewriteSheet = true } label: {
                        Label("AI Rewrite", systemImage: "sparkles")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(.white)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(viewModel.isProcessing)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)

                    // ── Model chip ────────────────────────────────────────────
                    if !viewModel.modelName.isEmpty {
                        HStack {
                            Text(viewModel.modelName)
                                .font(.caption2).foregroundStyle(.secondary)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Color(.secondarySystemFill), in: Capsule())
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        // Safe-area-aware bottom padding so the model chip isn't
                        // hidden behind the home indicator on Face ID devices.
                        .padding(.bottom, 20)
                    }
                }
                // Ensure bottom content clears the home indicator.
                .padding(.bottom, 8)
            }
            .navigationTitle("Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .overlay { if viewModel.isProcessing { processingOverlay } }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { onDismissAll?() ?? dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { viewModel.copyToClipboard() } label: {
                        Image(systemName: viewModel.didCopy ? "checkmark" : "doc.on.doc")
                    }
                    .symbolEffect(.bounce, value: viewModel.didCopy)
                    Button { shareItem = ShareItem(text: viewModel.text) } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(viewModel.text.isEmpty)
                    Button(role: .destructive) { showDeleteConfirmation = true } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            .sheet(item: $shareItem) { ShareSheet(text: $0.text) }
            .sheet(isPresented: $showRewriteSheet) {
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
            .confirmationDialog("Delete this transcription?",
                                isPresented: $showDeleteConfirmation,
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) { viewModel.delete(); dismiss() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This action cannot be undone.") }
            .alert("Error", isPresented: Binding(
                get: { viewModel.deleteError != nil || viewModel.processingError != nil },
                set: { if !$0 { viewModel.clearError(); viewModel.dismissProcessingError() } }
            )) {
                Button("OK") { viewModel.clearError(); viewModel.dismissProcessingError() }
            } message: {
                Text(viewModel.deleteError?.localizedDescription ?? viewModel.processingError ?? "")
            }
        }
    }

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().scaleEffect(1.4).tint(.white)
                Text("Processing AI rewrite...")
                    .font(.subheadline).foregroundStyle(.white)
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

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
}

private struct ShareItem: Identifiable { let id = UUID(); let text: String }
private struct ShareSheet: UIViewControllerRepresentable {
    let text: String
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
