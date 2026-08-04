import SwiftUI

/// Modal Sheet view presenting AI rewrite presets, custom prompt execution, and prompt library templates.
public struct RewriteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var viewModel: TranscriptViewModel
    @ObservedObject public var settingsViewModel: SettingsViewModel
    
    @State private var customPromptText: String = ""
    @State private var activeTab: Int = 0 // 0: Presets, 1: Custom Prompt, 2: Library
    @StateObject private var promptService = PromptService()
    
    public init(
        viewModel: TranscriptViewModel,
        settingsViewModel: SettingsViewModel
    ) {
        self.viewModel = viewModel
        self.settingsViewModel = settingsViewModel
    }
    
    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Segmented control tabs
                Picker("Rewrite Mode", selection: $activeTab) {
                    Text("Presets").tag(0)
                    Text("Custom Prompt").tag(1)
                    Text("Library").tag(2)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                Divider()
                
                if activeTab == 0 {
                    // Presets Grid / List
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(VersionType.PresetType.allCases) { preset in
                                Button(action: {
                                    Task {
                                        dismiss()
                                        await viewModel.performRewrite(preset: preset, config: settingsViewModel.config)
                                    }
                                }) {
                                    HStack(spacing: 16) {
                                        iconForPreset(preset)
                                            .font(.title3)
                                            .foregroundColor(.blue)
                                            .frame(width: 32, height: 32)
                                            .background(Color.blue.opacity(0.12))
                                            .cornerRadius(8)
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(preset.rawValue)
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                            Text(preset.description)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "sparkles")
                                            .foregroundColor(.blue)
                                    }
                                    .padding(14)
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(12)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding()
                    }
                } else if activeTab == 1 {
                    // Custom Prompt Input
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Custom Prompt Instruction")
                            .font(.headline)
                        
                        TextEditor(text: $customPromptText)
                            .frame(height: 120)
                            .padding(8)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                        
                        Text("Examples:")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            exampleButton("Rewrite this into a polite email.")
                            exampleButton("Convert this into Jira tasks.")
                            exampleButton("Make it concise and direct.")
                            exampleButton("Translate to Spanish.")
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            Task {
                                dismiss()
                                await viewModel.performCustomRewrite(prompt: customPromptText, config: settingsViewModel.config)
                            }
                        }) {
                            HStack {
                                Image(systemName: "sparkles")
                                Text("Generate Rewrite")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(customPromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.blue)
                            .cornerRadius(12)
                        }
                        .disabled(customPromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding()
                } else {
                    // Prompt Library Tab
                    PromptPicker(promptService: promptService) { template in
                        Task {
                            dismiss()
                            await viewModel.performTemplateRewrite(template: template, config: settingsViewModel.config)
                        }
                    }
                    .padding(.top)
                }
            }
            .navigationTitle("AI Rewrite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    @ViewBuilder
    private func exampleButton(_ exampleText: String) -> some View {
        Button(action: { customPromptText = exampleText }) {
            Text("• \"\(exampleText)\"")
                .font(.caption)
                .foregroundColor(.blue)
        }
    }
    
    @ViewBuilder
    private func iconForPreset(_ preset: VersionType.PresetType) -> Image {
        switch preset {
        case .professional: return Image(systemName: "briefcase.fill")
        case .meetingNotes: return Image(systemName: "doc.text.fill")
        case .summary: return Image(systemName: "text.alignleft")
        case .bulletPoints: return Image(systemName: "list.bullet")
        case .email: return Image(systemName: "envelope.fill")
        case .blogStyle: return Image(systemName: "newspaper.fill")
        case .socialMediaPost: return Image(systemName: "bubble.left.and.bubble.right.fill")
        case .actionItems: return Image(systemName: "checkmark.square.fill")
        }
    }
}
