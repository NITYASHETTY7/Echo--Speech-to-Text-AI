//
//  HistoryView.swift
//  Echo
//
//  List of transcription cards with swipe-to-delete, tap to open, search,
//  and an empty state. V3: aiService injected into TranscriptViewModel.
//

import SwiftUI
import EchoCore

struct HistoryView: View {

    @Environment(\.transcriptionStore) private var transcriptionStore
    @Environment(\.aiService) private var aiService
    @Environment(ProviderSettings.self) private var providerSettings
    @Environment(Preferences.self) private var preferences

    @State private var viewModel: HistoryViewModel?
    @State private var selectedTranscription: Transcription?
    @State private var showDeleteAllConfirmation = false

    var body: some View {
        Group {
            if let vm = viewModel {
                historyContent(vm: vm)
            } else {
                ProgressView("Loading…")
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let store = transcriptionStore else { return }
            if viewModel == nil {
                viewModel = HistoryViewModel(store: store)
                viewModel?.load()
            }
        }
    }

    @ViewBuilder
    private func historyContent(vm: HistoryViewModel) -> some View {
        let items = vm.filteredTranscriptions
        Group {
            if vm.isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty && vm.searchText.isEmpty {
                // Empty state — centred vertically in available space on all devices
                GeometryReader { geo in
                    ScrollView {
                        EmptyStateView(
                            systemImage: "clock.arrow.circlepath",
                            title: "No History",
                            subtitle: "Your transcriptions will appear here after you record."
                        )
                        .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
            } else if items.isEmpty {
                GeometryReader { geo in
                    ScrollView {
                        EmptyStateView(
                            systemImage: "magnifyingglass",
                            title: "No Results",
                            subtitle: "No transcriptions match \"\(vm.searchText)\"."
                        )
                        .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
            } else {
                listContent(vm: vm, items: items)
            }
        }
        .searchable(text: Binding(get: { vm.searchText }, set: { vm.searchText = $0 }),
                    prompt: "Search transcriptions")
        .toolbar {
            if !items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Delete All", role: .destructive) { showDeleteAllConfirmation = true }
                        .foregroundStyle(.red)
                }
            }
        }
        .confirmationDialog("Delete All Transcriptions?", isPresented: $showDeleteAllConfirmation,
                            titleVisibility: .visible) {
            Button("Delete All", role: .destructive) { vm.deleteAll() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This will permanently delete all \(items.count) transcriptions.") }
        .alert("Error", isPresented: Binding(
            get: { vm.storeError != nil },
            set: { if !$0 { vm.clearError() } }
        )) {
            Button("OK", role: .cancel) { vm.clearError() }
        } message: { Text(vm.storeError?.localizedDescription ?? "A store error occurred.") }
        .navigationDestination(for: Transcription.self) { t in
            if let store = transcriptionStore {
                let tvm = TranscriptViewModel(transcription: t, store: store, aiService: aiService, preferences: preferences)
                TranscriptView(viewModel: tvm)
            }
        }
        .sheet(item: $selectedTranscription) { t in
            if let store = transcriptionStore {
                let tvm = TranscriptViewModel(transcription: t, store: store, aiService: aiService, preferences: preferences)
                TranscriptDetailSheet(viewModel: tvm) { selectedTranscription = nil }
            }
        }
    }

    @ViewBuilder
    private func listContent(vm: HistoryViewModel, items: [Transcription]) -> some View {
        let currentProvider = ProviderId(rawValue: providerSettings.selectedProvider)
        List {
            ForEach(items) { transcription in
                Button { selectedTranscription = transcription } label: {
                    TranscriptCard(transcription: transcription, providerId: currentProvider)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowSeparator(.hidden)
                // Prevent list row background from showing through on light mode
                .listRowBackground(Color(.systemBackground))
            }
            .onDelete { indexSet in
                for index in indexSet { vm.delete(id: items[index].id) }
            }
        }
        .listStyle(.plain)
        .refreshable { vm.load() }
    }
}
