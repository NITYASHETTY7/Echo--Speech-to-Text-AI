import Foundation

/// Protocol defining Prompt Template Management contract.
public protocol PromptServiceProtocol {
    func getTemplates() -> [PromptTemplate]
    func getTemplates(for category: PromptCategory) -> [PromptTemplate]
    func addCustomTemplate(_ template: PromptTemplate)
    func removeCustomTemplate(id: UUID)
    func resetToDefaults()
}

/// Service managing built-in and custom prompt templates.
public class PromptService: PromptServiceProtocol {
    private var templates: [PromptTemplate]
    private let userDefaults: UserDefaults
    private let storageKey = "Echo_PromptTemplates_v2"
    
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.templates = PromptTemplate.defaultTemplates
        loadSavedTemplates()
    }
    
    public func getTemplates() -> [PromptTemplate] {
        return templates
    }
    
    public func getTemplates(for category: PromptCategory) -> [PromptTemplate] {
        return templates.filter { $0.category == category }
    }
    
    public func addCustomTemplate(_ template: PromptTemplate) {
        templates.append(template)
        saveTemplates()
    }
    
    public func removeCustomTemplate(id: UUID) {
        templates.removeAll { $0.id == id && !$0.isBuiltIn }
        saveTemplates()
    }
    
    public func resetToDefaults() {
        templates = PromptTemplate.defaultTemplates
        userDefaults.removeObject(forKey: storageKey)
    }
    
    private func saveTemplates() {
        let customOnly = templates.filter { !$0.isBuiltIn }
        if let data = try? JSONEncoder().encode(customOnly) {
            userDefaults.set(data, forKey: storageKey)
        }
    }
    
    private func loadSavedTemplates() {
        guard let data = userDefaults.data(forKey: storageKey),
              let customSaved = try? JSONDecoder().decode([PromptTemplate].self, from: data) else {
            return
        }
        // Combine built-in templates with loaded custom templates
        var combined = PromptTemplate.defaultTemplates
        for custom in customSaved {
            if !combined.contains(where: { $0.id == custom.id }) {
                combined.append(custom)
            }
        }
        self.templates = combined
    }
}
