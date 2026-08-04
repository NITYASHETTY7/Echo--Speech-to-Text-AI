import Foundation
import Combine

/// ViewModel managing settings, LLM provider selection, and grammar correction toggle.
@MainActor
public class SettingsViewModel: ObservableObject {
    @Published public var config: LLMConfig {
        didSet {
            saveConfig()
        }
    }
    
    private let userDefaults: UserDefaults
    private let storageKey = "Echo_LLM_Config_v2"
    
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let data = userDefaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(LLMConfig.self, from: data) {
            self.config = saved
        } else {
            self.config = LLMConfig.defaultConfig
        }
    }
    
    public var isGrammarCorrectionEnabled: Bool {
        get { config.isGrammarCorrectionEnabled }
        set { config.isGrammarCorrectionEnabled = newValue }
    }
    
    public var selectedProvider: LLMProvider {
        get { config.provider }
        set {
            config.provider = newValue
            if config.modelName.isEmpty {
                config.modelName = newValue.defaultModel
            }
        }
    }
    
    public func resetToDefaults() {
        self.config = LLMConfig.defaultConfig
    }
    
    private func saveConfig() {
        if let data = try? JSONEncoder().encode(config) {
            userDefaults.set(data, forKey: storageKey)
        }
    }
}
