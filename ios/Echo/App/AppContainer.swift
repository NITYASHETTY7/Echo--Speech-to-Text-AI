import Foundation
import Combine

/// Dependency Injection Container for Echo V2 application services and view models.
public class AppContainer {
    public static let shared = AppContainer()
    
    public let llmProviderService: LLMProviderServiceProtocol
    public let grammarCorrectionService: GrammarCorrectionServiceProtocol
    public let rewriteService: RewriteServiceProtocol
    public let promptService: PromptServiceProtocol
    public let exportService: ExportServiceProtocol
    public let storage: TranscriptStorageProtocol
    public let sttService: SpeechToTextServiceProtocol
    
    // Future expansion services
    public let translationService: TranslationServiceProtocol
    public let toneAdjustmentService: ToneAdjustmentServiceProtocol
    public let simplificationService: SimplificationServiceProtocol
    public let domainFormattingService: DomainFormattingServiceProtocol
    
    public init(
        llmProviderService: LLMProviderServiceProtocol = LLMProviderService(),
        grammarCorrectionService: GrammarCorrectionServiceProtocol = GrammarCorrectionService(),
        rewriteService: RewriteServiceProtocol = RewriteService(),
        promptService: PromptServiceProtocol = PromptService(),
        exportService: ExportServiceProtocol = ExportService(),
        storage: TranscriptStorageProtocol = TranscriptStorage(),
        sttService: SpeechToTextServiceProtocol = SpeechToTextService()
    ) {
        self.llmProviderService = llmProviderService
        self.grammarCorrectionService = grammarCorrectionService
        self.rewriteService = rewriteService
        self.promptService = promptService
        self.exportService = exportService
        self.storage = storage
        self.sttService = sttService
        
        self.translationService = TranslationService(llmService: llmProviderService)
        self.toneAdjustmentService = ToneAdjustmentService(llmService: llmProviderService)
        self.simplificationService = SimplificationService(llmService: llmProviderService)
        self.domainFormattingService = DomainFormattingService(llmService: llmProviderService)
    }
}
