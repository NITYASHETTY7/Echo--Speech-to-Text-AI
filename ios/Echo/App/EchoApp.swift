import SwiftUI

@main
struct EchoApp: App {
    @StateObject private var settingsViewModel = SettingsViewModel()
    @StateObject private var transcriptViewModel = TranscriptViewModel()
    @StateObject private var historyViewModel = HistoryViewModel()
    
    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationView {
                    TranscriptView(
                        viewModel: transcriptViewModel,
                        settingsViewModel: settingsViewModel
                    )
                }
                .tabItem {
                    Label("Transcribe", systemImage: "mic.fill")
                }
                
                NavigationView {
                    HistoryView(
                        viewModel: historyViewModel,
                        onSelectTranscript: { transcript in
                            transcriptViewModel.currentTranscript = transcript
                            transcriptViewModel.activeVersion = transcript.activeVersion
                        }
                    )
                }
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }
                
                NavigationView {
                    SettingsView(viewModel: settingsViewModel)
                }
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
    }
}
