//
//  PromptTemplate.swift
//  EchoCore
//
//  Mirrors Android's domain.ai.PromptTemplate data class and PromptCategory enum.
//

import Foundation

// MARK: - PromptCategory

public enum PromptCategory: String, Sendable, CaseIterable {
    case general        = "GENERAL"
    case business       = "BUSINESS"
    case productivity   = "PRODUCTIVITY"
    case communication  = "COMMUNICATION"
}

// MARK: - PromptTemplate

public struct PromptTemplate: Sendable {
    public let id: String
    public let title: String
    public let description: String
    public let category: PromptCategory
    public let systemPrompt: String
    /// The VersionType this template produces.
    public let targetVersionType: VersionType

    public init(
        id: String,
        title: String,
        description: String,
        category: PromptCategory,
        systemPrompt: String,
        targetVersionType: VersionType
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.category = category
        self.systemPrompt = systemPrompt
        self.targetVersionType = targetVersionType
    }
}
