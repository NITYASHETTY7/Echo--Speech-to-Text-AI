import SwiftUI

/// Main Transcription screen displaying raw/corrected/rewritten transcript, version selector, rewrite button, and export action.
public struct TranscriptView: View {
    @ObservedObject public var viewModel: TranscriptViewModel
    @ObservedObject public var settingsViewModel: SettingsViewModel
    
    @State private var sampleInputText: String = "this is a sample test transcription to demonstrate echo v2 grammar correction and ai rewrite features."
    
    public init(
        viewModel: TranscriptViewModel,
        settingsViewModel: SettingsViewModel
    ) {
        self.viewModel = viewModel
        self.settingsViewModel = settingsViewModel
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Version Selector Pill Bar
            if let transcript = viewModel.currentTranscript, !transcript.versions.isEmpty {
                VersionSelector(
                    versions: transcript.versions,
                    activeVersionId: viewModel.activeVersion?.id,
                    onSelectVersion: { id in
                        viewModel.selectVersion(id: id)
                    }
                )
                .padding(.top, 8)
                Divider().padding(.top, 8)
            }
            
            // Status / Loading Indicator
            if viewModel.isLoading {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(viewModel.statusMessage ?? "Processing...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue.opacity(0.1))
            }
            
            // Error banner if any
            if let err = viewModel.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding()
                .background(Color.orange.opacity(0.12))
            }
            
            // Transcript Display Text Area
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let active = viewModel.activeVersion {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(active.title)
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.blue)
                                    .textCase(.uppercase)
                                
                                Spacer()
                                
                                Text(dateFormatter.string(from: active.timestamp))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            Text(active.text)
                                .font(.body)
                                .lineSpacing(6)
                                .padding(.top, 8)
                                .textSelection(.enabled)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    } else {
                        // Empty state / Test Input Box
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Speech-to-Text Input")
                                .font(.headline)
                            
                            TextEditor(text: $sampleInputText)
                                .frame(height: 100)
                                .padding(6)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(8)
                            
                            Button(action: {
                                Task {
                                    await viewModel.processTranscription(rawText: sampleInputText, config: settingsViewModel.config)
                                }
                            }) {
                                HStack {
                                    Image(systemName: "mic.fill")
                                    Text("Transcribe Audio Input")
                                }
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(10)
                            }
                        }
                        .padding()
                    }
                }
                .padding()
            }
            
            Spacer()
            
            // Bottom Action Bar (Rewrite & Export buttons)
            if viewModel.currentTranscript != nil {
                HStack(spacing: 16) {
                    // Rewrite Button
                    Button(action: {
                        viewModel.isRewriteSheetPresented = true
                    }) {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("Rewrite")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing))
                        .cornerRadius(12)
                        .shadow(color: Color.purple.opacity(0.3), radius: 6, x: 0, y: 3)
                    }
                    
                    // Export Button
                    Button(action: {
                        viewModel.isExportSheetPresented = true
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export")
                        }
                        .font(.headline)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: -2)
            }
        }
        .navigationTitle("Echo Transcript")
        .sheet(isPresented: $viewModel.isRewriteSheetPresented) {
            RewriteSheet(viewModel: viewModel, settingsViewModel: settingsViewModel)
        }
        .sheet(isPresented: $viewModel.isExportSheetPresented) {
            ExportSheet(viewModel: viewModel)
        }
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }
}
