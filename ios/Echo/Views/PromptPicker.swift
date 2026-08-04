import SwiftUI

/// Component allowing browsing, filtering, and selecting prompt templates from the library.
public struct PromptPicker: View {
    @ObservedObject public var promptService: PromptService
    public let onSelectTemplate: (PromptTemplate) -> Void
    
    @State private var selectedCategory: PromptCategory = .general
    @State private var searchText: String = ""
    
    public init(
        promptService: PromptService = PromptService(),
        onSelectTemplate: @escaping (PromptTemplate) -> Void
    ) {
        self.promptService = promptService
        self.onSelectTemplate = onSelectTemplate
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Prompt Library")
                .font(.headline)
                .padding(.horizontal)
            
            // Category Filter Bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PromptCategory.allCases) { category in
                        let isSelected = category == selectedCategory
                        Button(action: { selectedCategory = category }) {
                            Text(category.rawValue)
                                .font(.caption)
                                .fontWeight(isSelected ? .bold : .regular)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(isSelected ? Color.blue.opacity(0.2) : Color(.tertiarySystemBackground))
                                .foregroundColor(isSelected ? .blue : .primary)
                                .cornerRadius(12)
                        }
                    }
                }
                .padding(.horizontal)
            }
            
            // Templates List
            let templates = filteredTemplates
            if templates.isEmpty {
                Text("No prompt templates found in this category.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(templates) { template in
                            Button(action: { onSelectTemplate(template) }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(template.title)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.primary)
                                        
                                        Text(template.description)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(12)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(10)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
    
    private var filteredTemplates: [PromptTemplate] {
        promptService.getTemplates().filter { template in
            let matchesCat = (selectedCategory == .general) || (template.category == selectedCategory)
            if searchText.isEmpty { return matchesCat }
            return matchesCat && (template.title.localizedCaseInsensitiveContains(searchText) || template.description.localizedCaseInsensitiveContains(searchText))
        }
    }
}
