import Foundation
import Combine

/// ViewModel driving Transcript recording, grammar correction, multi-version management, rewriting, and exporting.
@MainActor
public class TranscriptViewModel: ObservableObject {
    @Published public var currentTranscript: Transcript?
    @Published public var activeVersion: TranscriptVersion?
    @Published public var isLoading: Bool = false
    @Published public var statusMessage: String? = nil
    @Published public var errorMessage: String? = nil
    @Published public var isRewriteSheetPresented: Bool = false
    @Published public var isExportSheetPresented: Bool = false
    
    private let sttService: SpeechToTextServiceProtocol
    private let grammarCorrectionService: GrammarCorrectionServiceProtocol
    private let rewriteService: RewriteServiceProtocol
    private let exportService: ExportServiceProtocol
    private let storage: TranscriptStorageProtocol
    
    public init(
        sttService: SpeechToTextServiceProtocol = SpeechToTextService(),
        grammarCorrectionService: GrammarCorrectionServiceProtocol = GrammarCorrectionService(),
        rewriteService: RewriteServiceProtocol = RewriteService(),
        exportService: ExportServiceProtocol = ExportService(),
        storage: TranscriptStorageProtocol = TranscriptStorage()
    ) {
        self.sttService = sttService
        self.grammarCorrectionService = grammarCorrectionService
        self.rewriteService = rewriteService
        self.exportService = exportService
        self.storage = storage
    }
    
    // MARK: - Core Transcription Flow
    
    /// Processes incoming raw transcript text (or from STT audio recording).
    /// If grammar correction is enabled in LLMConfig, executes optional AI grammar correction step.
    public func processTranscription(rawText: String, config: LLMConfig, audioPath: String? = nil) async {
        isLoading = true
        statusMessage = "Processing transcript..."
        errorMessage = nil
        
        let originalVersion = TranscriptVersion(text: rawText, type: .original)
        var versions = [originalVersion]
        var activeId = originalVersion.id
        
        if config.isGrammarCorrectionEnabled {
            statusMessage = "Applying AI Grammar Correction..."
            do {
                let correctedText = try await grammarCorrectionService.correctGrammar(rawTranscript: rawText, config: config)
                if !correctedText.isEmpty && correctedText != rawText {
                    let correctedVersion = TranscriptVersion(text: correctedText, type: .grammarCorrected)
                    versions.append(correctedVersion)
                    activeId = correctedVersion.id
                }
            } catch {
                print("Grammar correction error: \(error.localizedDescription)")
                // Pipeline continues cleanly with raw transcript if grammar correction fails
            }
        }
        
        var transcript = Transcript(
            versions: versions,
            activeVersionId: activeId,
            audioPath: audioPath
        )
        
        self.currentTranscript = transcript
        self.activeVersion = transcript.activeVersion
        
        // Save to persistent storage
        try? storage.saveTranscript(transcript)
        
        isLoading = false
        statusMessage = nil
    }
    
    /// Transcribe audio from file URL
    public func transcribeAudio(url: URL, config: LLMConfig) async {
        isLoading = true
        statusMessage = "Transcribing audio..."
        
        do {
            let rawText = try await sttService.transcribeAudio(url: url)
            await processTranscription(rawText: rawText, config: config, audioPath: url.path)
        } catch {
            errorMessage = "Transcription failed: \(error.localizedDescription)"
            isLoading = false
            statusMessage = nil
        }
    }
    
    // MARK: - Version Management
    
    /// Select active version by ID.
    public func selectVersion(id: UUID) {
        guard var transcript = currentTranscript else { return }
        if transcript.versions.contains(where: { $0.id == id }) {
            transcript.activeVersionId = id
            self.currentTranscript = transcript
            self.activeVersion = transcript.activeVersion
            try? storage.saveTranscript(transcript)
        }
    }
    
    /// Select active version by VersionType.
    public func selectVersion(type: VersionType) {
        guard let version = currentTranscript?.versions.first(where: { $0.type == type }) else { return }
        selectVersion(id: version.id)
    }
    
    // MARK: - Feature 2: AI Rewrite
    
    /// Rewrites active transcript using preset.
    public func performRewrite(preset: VersionType.PresetType, config: LLMConfig) async {
        guard let textToRewrite = activeVersion?.text ?? currentTranscript?.originalVersion?.text else {
            errorMessage = "No text available to rewrite."
            return
        }
        
        isLoading = true
        statusMessage = "Generating \(preset.rawValue) version..."
        errorMessage = nil
        
        do {
            let result = try await rewriteService.rewrite(transcript: textToRewrite, preset: preset, config: config)
            appendVersion(result.versionCreated)
        } catch {
            errorMessage = "Rewrite failed: \(error.localizedDescription)"
        }
        
        isLoading = false
        statusMessage = nil
    }
    
    /// Rewrites active transcript using custom prompt.
    public func performCustomRewrite(prompt: String, config: LLMConfig) async {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }
        
        guard let textToRewrite = activeVersion?.text ?? currentTranscript?.originalVersion?.text else {
            errorMessage = "No text available to rewrite."
            return
        }
        
        isLoading = true
        statusMessage = "Executing custom rewrite..."
        errorMessage = nil
        
        do {
            let result = try await rewriteService.rewriteCustom(transcript: textToRewrite, customPrompt: trimmedPrompt, config: config)
            appendVersion(result.versionCreated)
        } catch {
            errorMessage = "Custom rewrite failed: \(error.localizedDescription)"
        }
        
        isLoading = false
        statusMessage = nil
    }
    
    /// Rewrites active transcript using prompt template.
    public func performTemplateRewrite(template: PromptTemplate, config: LLMConfig) async {
        guard let textToRewrite = activeVersion?.text ?? currentTranscript?.originalVersion?.text else {
            errorMessage = "No text available to rewrite."
            return
        }
        
        isLoading = true
        statusMessage = "Applying prompt template '\(template.title)'..."
        errorMessage = nil
        
        do {
            let result = try await rewriteService.rewriteWithTemplate(transcript: textToRewrite, template: template, config: config)
            appendVersion(result.versionCreated)
        } catch {
            errorMessage = "Template rewrite failed: \(error.localizedDescription)"
        }
        
        isLoading = false
        statusMessage = nil
    }
    
    private func appendVersion(_ version: TranscriptVersion) {
        guard var transcript = currentTranscript else { return }
        transcript.addVersion(version)
        self.currentTranscript = transcript
        self.activeVersion = version
        try? storage.saveTranscript(transcript)
    }
    
    // MARK: - Feature 6: Export
    
    /// Exports current active version into requested format.
    public func exportCurrentVersion(format: ExportFormat) -> ExportResult? {
        guard let version = activeVersion else { return nil }
        do {
            return try exportService.export(version: version, format: format)
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
            return nil
        }
    }
}
