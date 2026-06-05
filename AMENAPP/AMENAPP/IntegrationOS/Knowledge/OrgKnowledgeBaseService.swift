// OrgKnowledgeBaseService.swift — AMEN IntegrationOS
// Actor that calls the `orgKnowledgeSearch` Cloud Function.

import Foundation
import FirebaseFunctions
import FirebaseFirestore
import FirebaseAuth
import FirebaseRemoteConfig

actor OrgKnowledgeBaseService {
    static let shared = OrgKnowledgeBaseService()
    private init() {}

    private let functions = Functions.functions()
    private let db = Firestore.firestore()
    private let ledger = ConsentLedgerService.shared
    private let remoteConfig = RemoteConfig.remoteConfig()
    private var isEnabled: Bool { remoteConfig.configValue(forKey: "integration_knowledge_enabled").booleanValue }

    // MARK: - Search

    func search(orgId: String, query: String, category: KnowledgeCategory? = nil) async throws -> [KnowledgeSearchResult] {
        guard isEnabled else { return [] }
        guard await ledger.isGranted(scope: .orgKnowledgeRead, providerId: "amen") else {
            throw IntegrationOSError.consentDenied(.orgKnowledgeRead)
        }

        var payload: [String: Any] = ["orgId": orgId, "query": query]
        if let cat = category { payload["category"] = cat.rawValue }

        let result = try await functions.httpsCallable("orgKnowledgeSearch").call(payload)
        guard let data = result.data as? [String: Any],
              let items = data["results"] as? [[String: Any]] else { return [] }

        return items.compactMap { parseResult($0) }
    }

    // MARK: - Fetch All

    func fetchDocuments(orgId: String, category: KnowledgeCategory? = nil) async throws -> [OrgKnowledgeDocument] {
        guard isEnabled else { return [] }
        guard await ledger.isGranted(scope: .orgKnowledgeRead, providerId: "amen") else {
            throw IntegrationOSError.consentDenied(.orgKnowledgeRead)
        }
        var query: Query = db.collection("orgKnowledge")
            .whereField("orgId", isEqualTo: orgId)
            .whereField("isPublic", isEqualTo: true)
            .order(by: "updatedAt", descending: true)
            .limit(to: 50)

        if let cat = category {
            query = db.collection("orgKnowledge")
                .whereField("orgId", isEqualTo: orgId)
                .whereField("category", isEqualTo: cat.rawValue)
                .order(by: "updatedAt", descending: true)
                .limit(to: 50)
        }
        let snap = try await query.getDocuments()
        return snap.documents.compactMap { try? $0.data(as: OrgKnowledgeDocument.self) }
    }

    // MARK: - Write

    func addDocument(_ doc: OrgKnowledgeDocument) async throws {
        guard isEnabled else { return }
        guard await ledger.isGranted(scope: .orgKnowledgeWrite, providerId: "amen") else {
            throw IntegrationOSError.consentDenied(.orgKnowledgeWrite)
        }
        try db.collection("orgKnowledge").document(doc.id).setData(from: doc)
    }

    // MARK: - Parse

    private func parseResult(_ dict: [String: Any]) -> KnowledgeSearchResult? {
        guard let id = dict["id"] as? String,
              let title = dict["title"] as? String,
              let snippet = dict["snippet"] as? String else { return nil }
        let doc = OrgKnowledgeDocument(
            id: id,
            orgId: dict["orgId"] as? String ?? "",
            title: title,
            body: dict["body"] as? String ?? "",
            category: KnowledgeCategory(rawValue: dict["category"] as? String ?? "") ?? .resource,
            tags: dict["tags"] as? [String] ?? [],
            authorId: dict["authorId"] as? String ?? "",
            authorName: dict["authorName"] as? String ?? "",
            sourceURL: dict["sourceURL"] as? String,
            isPublic: dict["isPublic"] as? Bool ?? true,
            createdAt: Date(),
            updatedAt: Date()
        )
        return KnowledgeSearchResult(
            document: doc,
            relevanceScore: dict["score"] as? Double ?? 0,
            snippet: snippet
        )
    }
}
