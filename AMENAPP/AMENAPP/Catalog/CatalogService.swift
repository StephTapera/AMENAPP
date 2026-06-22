import Foundation
import FirebaseFirestore
import FirebaseFunctions

@MainActor
final class CatalogService: ObservableObject {

    static let shared = CatalogService()

    private let db = Firestore.firestore()
    private let functions = Functions.functions()

    private init() {}

    // MARK: - Works

    func fetchWorks(creatorId: String, type: WorkType?) async -> [CatalogWork] {
        var query: Query = db.collection("works")
            .whereField("creatorId", isEqualTo: creatorId)
            .whereField("reviewState", isEqualTo: WorkReviewState.published.rawValue)
            .whereField("deletedAt", isEqualTo: NSNull())
            .order(by: "publishedAt", descending: true)

        if let type {
            query = db.collection("works")
                .whereField("creatorId", isEqualTo: creatorId)
                .whereField("type", isEqualTo: type.rawValue)
                .whereField("reviewState", isEqualTo: WorkReviewState.published.rawValue)
                .whereField("deletedAt", isEqualTo: NSNull())
                .order(by: "publishedAt", descending: true)
        }

        do {
            let snapshot = try await query.getDocuments()
            let works = snapshot.documents.compactMap { CatalogWork(document: $0) }
            return works.filter {
                $0.visibility == .public || $0.visibility == .followers
            }
        } catch {
            return []
        }
    }

    func fetchWorksByTopic(creatorId: String, topic: String) async -> [CatalogWork] {
        do {
            let snapshot = try await db.collection("works")
                .whereField("creatorId", isEqualTo: creatorId)
                .whereField("topics", arrayContains: topic)
                .whereField("reviewState", isEqualTo: WorkReviewState.published.rawValue)
                .whereField("deletedAt", isEqualTo: NSNull())
                .order(by: "publishedAt", descending: true)
                .getDocuments()
            return snapshot.documents.compactMap { CatalogWork(document: $0) }
        } catch {
            return []
        }
    }

    func fetchKnowledgeNodes(creatorId: String) async -> [KnowledgeNode] {
        do {
            let snapshot = try await db.collection("knowledgeNodes")
                .whereField("creatorId", isEqualTo: creatorId)
                .whereField("deletedAt", isEqualTo: NSNull())
                .getDocuments()
            return snapshot.documents.compactMap { KnowledgeNode(document: $0) }
        } catch {
            return []
        }
    }

    func countByType(creatorId: String) async -> [WorkType: Int] {
        let all = await fetchWorks(creatorId: creatorId, type: nil)
        var counts: [WorkType: Int] = [:]
        for type in WorkType.allCases {
            counts[type] = all.filter { $0.type == type }.count
        }
        return counts
    }

    // MARK: - AI Query

    func askCreator(creatorId: String, question: String, userId: String) async throws -> AskCreatorResult {
        let result = try await functions.httpsCallable("askCreatorQuery").call([
            "creatorId": creatorId,
            "question": question,
            "userId": userId
        ])
        guard let data = result.data as? [String: Any] else {
            throw CatalogServiceError.invalidResponse
        }
        let citationDicts = data["citations"] as? [[String: Any]] ?? []
        let citations: [CatalogCitation] = citationDicts.compactMap { dict -> CatalogCitation? in
            guard
                let workId = dict["workId"] as? String,
                let snippet = dict["snippet"] as? String,
                let sourceUrl = dict["sourceUrl"] as? String
            else { return nil }
            return CatalogCitation(
                workId: workId,
                snippet: snippet,
                sourceUrl: sourceUrl,
                confidence: dict["confidence"] as? Double ?? 0
            )
        }
        return AskCreatorResult(
            answer: data["answer"] as? String ?? "",
            citations: citations,
            mode: data["mode"] as? String ?? "ai_summary",
            confidence: data["confidence"] as? Double ?? 0,
            refused: data["refused"] as? Bool ?? false
        )
    }

    // MARK: - Review Flow

    func advanceReviewState(workId: String) async throws {
        _ = try await functions.httpsCallable("advanceWorkReviewState").call(["workId": workId])
    }

    func publishWork(workId: String) async throws {
        _ = try await functions.httpsCallable("publishWork").call(["workId": workId])
    }
}

// MARK: - Errors

enum CatalogServiceError: Error {
    case invalidResponse
}
