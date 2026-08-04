import SwiftUI

/// Modal Sheet view presenting export format options (Plain Text, Markdown, PDF, DOCX).
public struct ExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var viewModel: TranscriptViewModel
    
    @State private var exportedResult: ExportResult? = nil
    @State private var showShareSheet: Bool = false
    @State private var exportMessage: String? = nil
    
    public init(viewModel: TranscriptViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                if let version = viewModel.activeVersion {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Exporting Active Version:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(version.title)
                            .font(.headline)
                        
                        Text("Text length: \(version.text.count) characters")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                }
                
                Text("Select Export Format")
                    .font(.headline)
                
                VStack(spacing: 12) {
                    ForEach(ExportFormat.allCases) { format in
                        Button(action: {
                            if let result = viewModel.exportCurrentVersion(format: format) {
                                self.exportedResult = result
                                self.exportMessage = "Exported as \(result.filename)"
                            }
                        }) {
                            HStack(spacing: 16) {
                                Image(systemName: format.iconName)
                                    .font(.title2)
                                    .foregroundColor(.blue)
                                    .frame(width: 40, height: 40)
                                    .background(Color.blue.opacity(0.12))
                                    .cornerRadius(10)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(format.rawValue)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text(".\(format.fileExtension) file format (\(format.mimeType))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundColor(.blue)
                            }
                            .padding(14)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                
                if let msg = exportMessage {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(msg)
                            .font(.subheadline)
                            .foregroundColor(.green)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(10)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Export Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
