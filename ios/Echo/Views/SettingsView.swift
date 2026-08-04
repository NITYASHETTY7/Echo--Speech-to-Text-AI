import SwiftUI

/// Settings view containing Grammar Correction toggle, LLM Provider selection, API key, and model configuration.
public struct SettingsView: View {
    @ObservedObject public var viewModel: SettingsViewModel
    
    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        Form {
            Section(header: Text("AI Transcription Features")) {
                Toggle(isOn: $viewModel.isGrammarCorrectionEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable Grammar Correction")
                            .font(.body)
                            .fontWeight(.medium)
                        Text("Automatically clean up grammar, punctuation, and capitalization upon transcription.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .tint(.blue)
            }
            
            Section(header: Text("LLM Provider Settings")) {
                Picker("Provider", selection: $viewModel.selectedProvider) {
                    ForEach(LLMProvider.allCases) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                
                HStack {
                    Text("Model Name")
                    Spacer()
                    TextField("Model", text: $viewModel.config.modelName)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("API Key")
                    Spacer()
                    SecureField("Enter API Key", text: $viewModel.config.apiKey)
                        .multilineTextAlignment(.trailing)
                }
                
                if viewModel.selectedProvider == .custom || viewModel.selectedProvider == .azure {
                    HStack {
                        Text("Endpoint URL")
                        Spacer()
                        TextField("https://...", text: Binding(
                            get: { viewModel.config.customEndpoint ?? "" },
                            set: { viewModel.config.customEndpoint = $0 }
                        ))
                        .multilineTextAlignment(.trailing)
                    }
                }
            }
            
            Section(header: Text("Grammar Correction Prompt")) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("System Prompt Used:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\"\(GrammarCorrectionService.systemPrompt)\"")
                        .font(.caption2)
                        .italic()
                        .foregroundColor(.primary)
                }
                .padding(.vertical, 4)
            }
            
            Section {
                Button(role: .destructive, action: {
                    viewModel.resetToDefaults()
                }) {
                    HStack {
                        Spacer()
                        Text("Reset Settings to Default")
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Settings")
    }
}
