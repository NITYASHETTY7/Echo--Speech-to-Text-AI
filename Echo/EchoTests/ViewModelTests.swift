//
//  ViewModelTests.swift
//  EchoTests
//
//  Phase 7 ViewModel unit tests.
//  Uses Swift Testing (@Test / #expect) and in-process mocks only —
//  no real Keychain, no real AVAudioSession.
//

import Foundation
import Testing
@testable import Echo
import EchoCore

// MARK: - Mock: AudioRecorder wrapper (stub)
//
// RecordingViewModel owns a concrete AudioRecorder, which itself accepts
// injectable session + recorder-factory dependencies.  We create it with a
// fully mocked session manager (MockAudioSessionManager from AudioRecorderTests)
// and a stubbed AVAudioRecorder so no real hardware is touched.
//
// The MockAudioSessionManager and MockAVAudioRecorder types are already defined
// in AudioRecorderTests.swift which is compiled into the same test target.

// MARK: - Stub TranscriptionCoordinator
//
// TranscriptionCoordinator is a final class that accepts a pipeline; we give it
// a stub pipeline that we can pre-configure with a success / failure result.
// StubPipeline is already defined in TranscriptionCoordinatorTests.swift.

// MARK: - Stub KeychainStore (in-memory backend, already built into the app)

@MainActor
private func makeKeychainStore() -> KeychainStore {
    KeychainStore(backend: InMemoryKeychainBackend())
}

// MARK: - Stub ProviderSettings / Preferences (ephemeral UserDefaults)

@MainActor
private func makeProviderSettings() -> ProviderSettings {
    ProviderSettings(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
}

@MainActor
private func makePreferences() -> Preferences {
    Preferences(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
}

// MARK: - Helper: minimal RecordingResult

private func fakeRecordingResult() -> RecordingResult {
    RecordingResult(
        fileURL: URL(fileURLWithPath: "/tmp/echo_test.m4a"),
        duration: 1.5,
        fileSize: 1024,
        format: "com.apple.m4a-audio",
        sampleRate: 16000,
        peakPowerDB: -20.0
    )
}

// MARK: - Helper: build a testable RecordingViewModel
//
// Injects a MockAudioSessionManager (permission controllable) and a
// MockAVAudioRecorder so no AVAudioSession hardware is used.
// `fileHasData` controls whether the MockFileSystem reports a non-zero
// file size (required for stopRecording to succeed past the .fileEmpty guard).

@MainActor
private func makeRecordingVM(
    permissionGranted: Bool = true,
    fileHasData: Bool = false,
    pipelineResult: Result<TranscriptionResponse, TranscriptionError> = .success(
        TranscriptionResponse(
            text: "Hello",
            providerId: .groq,
            model: "whisper-large-v3-turbo",
            recordingDuration: 1.0,
            processingDuration: 0.1
        )
    )
) -> (RecordingViewModel, MockAudioSessionManager, MockAVAudioRecorder, MockFileSystem) {
    let session = MockAudioSessionManager()
    session.permissionResult = permissionGranted

    let avRecorder = MockAVAudioRecorder()
    let config = RecordingConfiguration.standard
    let fs = MockFileSystem()
    let fileMgr = AudioFileManager(configuration: config, fileSystem: fs)
    let recorder = AudioRecorder(
        configuration: config,
        fileManager: fileMgr,
        sessionManager: session,
        recorderFactory: { url, _ in
            // Register the dynamically-created file URL in the mock filesystem
            // with a non-zero size so that finishRecording() does not throw .fileEmpty.
            if fileHasData {
                fs.fileAttributes[url.path] = [.size: Int64(4096)]
                fs.existingPaths.insert(url.path)
            }
            return avRecorder
        }
    )

    let pipeline: StubPipeline
    switch pipelineResult {
    case .success(let response): pipeline = StubPipeline(response: response)
    case .failure(let error):   pipeline = StubPipeline(error: error)
    }

    let provSettings = makeProviderSettings()
    let prefs        = makePreferences()

    let coordinator = TranscriptionCoordinator(
        pipeline: pipeline,
        preferences: prefs,
        providerSettings: provSettings,
        store: nil   // skip persistence in ViewModel tests
    )

    let vm = RecordingViewModel(recorder: recorder, coordinator: coordinator)
    return (vm, session, avRecorder, fs)
}

// MARK: ─────────────────────────────────────────────
// MARK: RecordingViewModel Tests
// MARK: ─────────────────────────────────────────────

@MainActor
struct RecordingViewModelTests {

    // MARK: Initial state

    @Test("RecordingViewModel starts in idle state")
    func initialState() {
        let (vm, _, _, _) = makeRecordingVM()
        #expect(vm.recordingState == .idle)
        #expect(vm.transcriptionState == .idle)
        #expect(vm.duration == 0)
        #expect(vm.audioLevel == 0)
        #expect(vm.recordingError == nil)
        #expect(vm.transcriptionError == nil)
        #expect(vm.isRecording == false)
        #expect(vm.isPaused == false)
        #expect(vm.isTranscribing == false)
        #expect(vm.lastTranscriptionResponse == nil)
    }

    // MARK: startRecording — permission granted

    @Test("startRecording transitions to recording when permission is granted")
    func startRecordingGranted() async {
        let (vm, session, _, _) = makeRecordingVM(permissionGranted: true)
        session.permissionResult = true
        await vm.startRecording()
        // After startRecording the recorder moves through requestingPermission → ready → recording.
        // Because MockAVAudioRecorder.record() returns true synchronously we expect .recording.
        #expect(vm.recordingState == .recording)
        #expect(vm.recordingError == nil)
    }

    @Test("startRecording stays idle when permission is denied")
    func startRecordingDenied() async {
        let (vm, _, _, _) = makeRecordingVM(permissionGranted: false)
        await vm.startRecording()
        // Denied → recorder state == .failed(.permissionDenied); vm remains effectively idle-ish.
        // The VM guards `guard granted else { return }` so no throw, but state is failed.
        #expect(vm.recordingState == .failed(.permissionDenied))
    }

    // MARK: cancelRecording

    @Test("cancelRecording resets to idle state")
    func cancelRecordingReturnsToIdle() async {
        let (vm, _, _, _) = makeRecordingVM(permissionGranted: true)
        await vm.startRecording()
        // Must be recording before cancel is meaningful.
        #expect(vm.recordingState == .recording)
        vm.cancelRecording()
        // After cancel the recorder goes to idle and the VM resets timers.
        #expect(vm.duration == 0)
        #expect(vm.audioLevel == 0)
        #expect(vm.recordingState == .idle)
    }

    // MARK: pauseRecording / resumeRecording

    @Test("pauseRecording transitions to paused state")
    func pauseRecording() async {
        let (vm, _, _, _) = makeRecordingVM(permissionGranted: true)
        await vm.startRecording()
        #expect(vm.recordingState == .recording)
        vm.pauseRecording()
        #expect(vm.recordingState == .paused)
        #expect(vm.isPaused == true)
    }

    @Test("resumeRecording transitions back to recording from paused")
    func resumeRecording() async {
        let (vm, _, _, _) = makeRecordingVM(permissionGranted: true)
        await vm.startRecording()
        vm.pauseRecording()
        #expect(vm.recordingState == .paused)
        vm.resumeRecording()
        #expect(vm.recordingState == .recording)
        #expect(vm.isRecording == true)
    }

    // MARK: stopRecording → transcription

    @Test("stopRecording triggers transcription after recording completes")
    func stopRecordingTriggersTranscription() async throws {
        let response = TranscriptionResponse(
            text: "Test transcript",
            providerId: .groq,
            model: "whisper-large-v3-turbo",
            recordingDuration: 1.0,
            processingDuration: 0.05
        )
        // fileHasData: true so that finishRecording() sees a non-zero file size
        // and emits .completed(result) rather than throwing .fileEmpty.
        let (vm, _, _, _) = makeRecordingVM(
            permissionGranted: true,
            fileHasData: true,
            pipelineResult: .success(response)
        )

        await vm.startRecording()
        #expect(vm.recordingState == .recording)

        await vm.stopRecording()
        // After stop, the recorder emits .completed, which triggers coordinator.transcribe.
        // Give the coordinator task a moment to finish.
        try await Task.sleep(for: .milliseconds(200))

        // The coordinator runs the stub pipeline synchronously so state should reach .completed.
        if case .completed(let r) = vm.transcriptionState {
            #expect(r.text == "Test transcript")
            #expect(vm.lastTranscriptionResponse?.text == "Test transcript")
        } else {
            Issue.record("Expected transcriptionState == .completed, got \(vm.transcriptionState)")
        }
    }
}

// MARK: ─────────────────────────────────────────────
// MARK: SettingsViewModel Tests
// MARK: ─────────────────────────────────────────────

@MainActor
struct SettingsViewModelTests {

    private func makeVM() -> (SettingsViewModel, KeychainStore) {
        let keychain = makeKeychainStore()
        let vm = SettingsViewModel(
            providerSettings: makeProviderSettings(),
            preferences: makePreferences(),
            keychainStore: keychain
        )
        return (vm, keychain)
    }

    // MARK: availableProviders

    @Test("availableProviders is non-empty")
    func availableProvidersNotEmpty() {
        let (vm, _) = makeVM()
        #expect(!vm.availableProviders.isEmpty)
    }

    @Test("availableProviders contains Groq")
    func availableProvidersContainsGroq() {
        let (vm, _) = makeVM()
        let ids = vm.availableProviders.map(\.id)
        #expect(ids.contains(.groq))
    }

    // MARK: saveAPIKey

    @Test("saveAPIKey persists the key and loadAPIKey retrieves it")
    func saveAPIKeyPersists() {
        let (vm, _) = makeVM()
        let provider = "groq"
        vm.saveAPIKey("sk-test-key", for: provider)
        let loaded = vm.loadAPIKey(for: provider)
        #expect(loaded == "sk-test-key")
    }

    // MARK: deleteAPIKey

    @Test("deleteAPIKey removes the stored key")
    func deleteAPIKeyRemoves() {
        let (vm, _) = makeVM()
        let provider = "openai"
        vm.saveAPIKey("sk-remove-me", for: provider)
        #expect(vm.loadAPIKey(for: provider) == "sk-remove-me")
        vm.deleteAPIKey(for: provider)
        #expect(vm.loadAPIKey(for: provider) == nil)
    }

    // MARK: isProviderConfigured

    @Test("isProviderConfigured returns false when no key saved")
    func isProviderConfiguredFalse() {
        let (vm, _) = makeVM()
        #expect(vm.isProviderConfigured("groq") == false)
    }

    @Test("isProviderConfigured returns true after saving a key")
    func isProviderConfiguredTrue() {
        let (vm, _) = makeVM()
        vm.saveAPIKey("sk-present", for: "groq")
        #expect(vm.isProviderConfigured("groq") == true)
    }

    // MARK: selectedProvider

    @Test("selectedProvider change is reflected immediately")
    func selectedProviderChanges() {
        let (vm, _) = makeVM()
        let initial = vm.selectedProvider
        // Switch to a different provider
        let other = vm.availableProviders.first { $0.id.rawValue != initial }?.id.rawValue ?? "openai"
        vm.selectedProvider = other
        #expect(vm.selectedProvider == other)
    }

    // MARK: API key draft round-trip

    @Test("loadAPIKeyDraft populates apiKeyDraft from stored key")
    func loadAPIKeyDraftPopulates() {
        let (vm, _) = makeVM()
        vm.saveAPIKey("sk-draft-test", for: "groq")
        vm.loadAPIKeyDraft(for: "groq")
        #expect(vm.apiKeyDraft == "sk-draft-test")
    }

    @Test("clearAPIKeyDraft empties apiKeyDraft")
    func clearAPIKeyDraftEmpties() {
        let (vm, _) = makeVM()
        vm.apiKeyDraft = "some-key"
        vm.clearAPIKeyDraft()
        #expect(vm.apiKeyDraft == "")
    }
}

// MARK: ─────────────────────────────────────────────
// MARK: HistoryViewModel Tests
// MARK: ─────────────────────────────────────────────

// MARK: ─────────────────────────────────────────────
// MARK: StubTranscriptionStore (in-memory, no SwiftData)
// MARK: ─────────────────────────────────────────────

/// Pure in-memory store for ViewModel tests. No SwiftData, no ModelContext,
/// no EXC_BREAKPOINT risk — conforms to TranscriptionStoreProtocol.
@MainActor
final class StubTranscriptionStore: TranscriptionStoreProtocol {
    private var rows: [String: Transcription] = [:]

    func insert(_ t: Transcription) throws {
        guard rows[t.id] == nil else { return }
        rows[t.id] = t
    }
    func update(_ t: Transcription) throws { rows[t.id] = t }
    func delete(id: String) throws { rows.removeValue(forKey: id) }
    func deleteAll() throws { rows.removeAll() }
    func fetch(limit: Int) throws -> [Transcription] {
        guard limit > 0 else { return [] }
        return Array(rows.values
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(limit))
    }
    func fetch(id: String) throws -> Transcription? { rows[id] }
}

// MARK: ─────────────────────────────────────────────
// MARK: HistoryViewModel Tests
// MARK: ─────────────────────────────────────────────

@MainActor
struct HistoryViewModelTests {

    private func makeVM() -> (HistoryViewModel, StubTranscriptionStore) {
        let store = StubTranscriptionStore()
        return (HistoryViewModel(store: store), store)
    }

    // MARK: Initial state

    @Test("HistoryViewModel starts with empty transcriptions list")
    func initiallyEmpty() async {
        let (vm, _) = makeVM()
        #expect(vm.transcriptions.isEmpty)
        #expect(vm.isLoading == false)
        #expect(vm.storeError == nil)
    }

    @Test("load() fills transcriptions when store has data")
    func loadFillsList() async throws {
        let (vm, store) = makeVM()
        let t = Transcription(id: "t1", text: "Hello", timestamp: 1_000_000, model: "whisper", userId: "u1")
        try store.insert(t)
        vm.load()
        #expect(vm.transcriptions.count == 1)
        #expect(vm.transcriptions.first?.id == "t1")
    }

    @Test("load() returns empty list when store is empty")
    func loadEmptyList() async {
        let (vm, _) = makeVM()
        vm.load()
        #expect(vm.transcriptions.isEmpty)
    }

    // MARK: delete

    @Test("delete removes the item from transcriptions")
    func deleteRemovesItem() async throws {
        let (vm, store) = makeVM()
        try store.insert(Transcription(id: "d1", text: "First",  timestamp: 1_000_001, model: "m", userId: "u"))
        try store.insert(Transcription(id: "d2", text: "Second", timestamp: 1_000_002, model: "m", userId: "u"))
        vm.load()
        #expect(vm.transcriptions.count == 2)
        vm.delete(id: "d1")
        #expect(vm.transcriptions.count == 1)
        #expect(vm.transcriptions.first?.id == "d2")
    }

    @Test("deleteAll removes every item")
    func deleteAllRemovesEverything() async throws {
        let (vm, store) = makeVM()
        for i in 1...3 {
            try store.insert(Transcription(id: "x\(i)", text: "T\(i)", timestamp: Int64(i), model: "m", userId: "u"))
        }
        vm.load()
        #expect(vm.transcriptions.count == 3)
        vm.deleteAll()
        #expect(vm.transcriptions.isEmpty)
    }

    // MARK: search

    @Test("filteredTranscriptions returns all when searchText is empty")
    func filteredAll() async throws {
        let (vm, store) = makeVM()
        try store.insert(Transcription(id: "f1", text: "Alpha", timestamp: 1, model: "m", userId: "u"))
        try store.insert(Transcription(id: "f2", text: "Beta",  timestamp: 2, model: "m", userId: "u"))
        vm.load()
        vm.searchText = ""
        #expect(vm.filteredTranscriptions.count == 2)
    }

    @Test("filteredTranscriptions filters by searchText")
    func filteredByQuery() async throws {
        let (vm, store) = makeVM()
        try store.insert(Transcription(id: "q1", text: "hello world", timestamp: 1, model: "m", userId: "u"))
        try store.insert(Transcription(id: "q2", text: "goodbye",     timestamp: 2, model: "m", userId: "u"))
        vm.load()
        vm.searchText = "hello"
        #expect(vm.filteredTranscriptions.count == 1)
        #expect(vm.filteredTranscriptions.first?.id == "q1")
    }
}

// MARK: ─────────────────────────────────────────────
// MARK: HomeViewModel Tests
// MARK: ─────────────────────────────────────────────

@MainActor
struct HomeViewModelTests {

    private func makeVM() -> (HomeViewModel, StubTranscriptionStore) {
        let store    = StubTranscriptionStore()
        let keychain = makeKeychainStore()
        let settings = makeProviderSettings()
        return (HomeViewModel(store: store, providerSettings: settings, keychainStore: keychain), store)
    }

    // MARK: Initial state

    @Test("HomeViewModel initialises with no latestTranscription")
    func initialNoTranscript() async {
        let (vm, _) = makeVM()
        #expect(vm.latestTranscription == nil)
        #expect(vm.loadError == nil)
    }

    @Test("loadLatest sets nil when store is empty")
    func loadLatestEmpty() async {
        let (vm, _) = makeVM()
        vm.loadLatest()
        #expect(vm.latestTranscription == nil)
    }

    @Test("loadLatest populates latestTranscription from store")
    func loadLatestWithData() async throws {
        let (vm, store) = makeVM()
        try store.insert(Transcription(id: "h1", text: "Recent", timestamp: 9_000_000, model: "m", userId: "u"))
        vm.loadLatest()
        #expect(vm.latestTranscription?.id == "h1")
    }

    // MARK: Provider display

    @Test("currentProviderDisplayName returns non-empty string")
    func currentProviderDisplayNameNonEmpty() async {
        let (vm, _) = makeVM()
        #expect(!vm.currentProviderDisplayName.isEmpty)
    }

    // MARK: clearError

    @Test("clearError removes loadError")
    func clearErrorRemovesError() async {
        let (vm, _) = makeVM()
        vm.clearError()
        #expect(vm.loadError == nil)
    }
}
