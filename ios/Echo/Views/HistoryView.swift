import SwiftUI

/// View rendering history of transcriptions with status badges and search across all versions.
public struct HistoryView: View {
    @ObservedObject public var viewModel: HistoryViewModel
    public let onSelectTranscript: (Transcript) -> Void
    
    public init(
        viewModel: HistoryViewModel,
        onSelectTranscript: @escaping (Transcript) -> Void
    ) {
        self.viewModel = viewModel
        self.onSelectTranscript = onSelectTranscript
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search all versions & transcripts...", text: $viewModel.searchQuery)
                    .textFieldStyle(PlainTextFieldStyle())
                if !viewModel.searchQuery.isEmpty {
                    Button(action: { viewModel.searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(10)
            .padding(.horizontal)
            .padding(.top, 8)
            
            // Badge Filter Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterPill(title: "All", badgeType: nil)
                    ForEach(TranscriptBadgeType.allCases, id: \.rawValue) { badge in
                        filterPill(title: badge.rawValue, badgeType: badge)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            
            Divider()
            
            // List of Transcripts
            if viewModel.filteredTranscripts.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No transcripts found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(viewModel.filteredTranscripts) { transcript in
                        Button(action: { onSelectTranscript(transcript) }) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(dateString(for: transcript.createdAt))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    Spacer()
                                    
                                    BadgeView(badgeType: transcript.badgeType)
                                }
                                
                                Text(transcript.activeVersion?.text ?? "Empty transcript")
                                    .font(.subheadline)
                                    .lineLimit(3)
                                    .foregroundColor(.primary)
                                
                                HStack(spacing: 6) {
                                    Image(systemName: "square.stack.3d.up")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text("\(transcript.versions.count) version\(transcript.versions.count == 1 ? "" : "s")")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.deleteTranscript(id: transcript.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(PlainListStyle())
            }
        }
        .navigationTitle("Transcript History")
        .onAppear {
            viewModel.loadTranscripts()
        }
    }
    
    @ViewBuilder
    private func filterPill(title: String, badgeType: TranscriptBadgeType?) -> some View {
        let isSelected = viewModel.selectedFilter == badgeType
        Button(action: { viewModel.selectedFilter = badgeType }) {
            Text(title)
                .font(.caption)
                .fontWeight(isSelected ? .bold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color(.tertiarySystemBackground))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(12)
        }
    }
    
    private func dateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
