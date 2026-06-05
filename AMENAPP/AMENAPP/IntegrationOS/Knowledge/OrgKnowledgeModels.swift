// OrgKnowledgeModels.swift — AMEN IntegrationOS

import Foundation

struct OrgKnowledgeDocument: Codable, Identifiable {
    var id: String = UUID().uuidString
    let orgId: String
    let title: String
    let body: String
    let category: KnowledgeCategory
    let tags: [String]
    let authorId: String
    let authorName: String
    let sourceURL: String?
    let isPublic: Bool
    let createdAt: Date
    let updatedAt: Date
}

enum KnowledgeCategory: String, Codable, CaseIterable {
    case policy = "policy"
    case teaching = "teaching"
    case faq = "faq"
    case announcement = "announcement"
    case resource = "resource"
    case liturgy = "liturgy"
}

struct KnowledgeSearchResult: Identifiable {
    var id: String { document.id }
    let document: OrgKnowledgeDocument
    let relevanceScore: Double
    let snippet: String
}

struct OrgAssistantMessage: Codable, Identifiable {
    var id: String = UUID().uuidString
    let role: AssistantRole
    let content: String
    let approved: Bool
    let timestamp: Date
    let citations: [String]
}

enum AssistantRole: String, Codable {
    case user, assistant
}
