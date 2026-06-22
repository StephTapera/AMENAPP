import Foundation
import FirebaseFirestore

// MARK: - AmenSemanticInsight
// users/{uid}/semanticInsights/{insightId}
// Persisted by the saveSemanticInsight Cloud Function — never written directly
// by the client to prevent client-trusted AI output writes.

struct AmenSemanticInsight: Identifiable, Codable {
    @DocumentID var id: String?
    let term: String
    let definitionId: String
    let compactDefinition: String
    let sourceType: String         // "post" | "note" | "comment" | "selah" | "churchNote"
    let sourceId: String
    let relatedScriptureRefs: [String]
    let createdAt: Date
    var updatedAt: Date
    var userNote: String?
    var visibility: String         // "private" | "public"

    enum CodingKeys: String, CodingKey {
        case id, term, definitionId, compactDefinition
        case sourceType, sourceId, relatedScriptureRefs
        case createdAt, updatedAt, userNote, visibility
    }
}

// MARK: - AmenKnowledgeThread
// users/{uid}/knowledgeThreads/{threadId}
// A user-curated thread linking a primary term to related content across surfaces.

struct AmenKnowledgeThread: Identifiable, Codable {
    @DocumentID var id: String?
    let title: String
    let primaryTerm: String
    var sourceObjects: [ThreadSourceObject]
    var relatedScriptureRefs: [String]
    var savedInsightIds: [String]
    let createdAt: Date
    var updatedAt: Date
    var lastOpenedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, primaryTerm, sourceObjects
        case relatedScriptureRefs, savedInsightIds
        case createdAt, updatedAt, lastOpenedAt
    }
}

struct ThreadSourceObject: Codable, Identifiable {
    var id: String { "\(sourceType)-\(sourceId)" }
    let sourceType: String    // "post" | "note" | "church" | "media" | "prayer" | "reflection"
    let sourceId: String
    let displayTitle: String?
    let addedAt: Date
}

// MARK: - AmenPresenceSignal
// users/{uid}/presenceSignals/{signalId}
// Written by logPresenceSignal Cloud Function — never by the client directly.

struct AmenPresenceSignal: Identifiable, Codable {
    @DocumentID var id: String?
    let screen: String
    let signalType: String
    let sourceType: String?
    let sourceId: String?
    let createdAt: Date
    let privacyLevel: String    // "aggregate" | "minimal"
    let metadata: [String: String]

    enum CodingKeys: String, CodingKey {
        case id, screen, signalType, sourceType
        case sourceId, createdAt, privacyLevel, metadata
    }
}

// MARK: - AmenSemanticInsightRepository
// Fetches saved semantic insights for the current user from Firestore.

@MainActor
final class AmenSemanticInsightRepository: ObservableObject {
    @Published private(set) var insights: [AmenSemanticInsight] = []
    @Published private(set) var isLoading = false

    private let db = Firestore.firestore()
    private var listenerRegistration: ListenerRegistration?

    func startListening(uid: String) {
        guard listenerRegistration == nil else { return }
        isLoading = true

        listenerRegistration = db
            .collection("users").document(uid)
            .collection("semanticInsights")
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                self.isLoading = false
                self.insights = snapshot?.documents.compactMap {
                    try? $0.data(as: AmenSemanticInsight.self)
                } ?? []
            }
    }

    func stopListening() {
        listenerRegistration?.remove()
        listenerRegistration = nil
    }

    deinit {
        listenerRegistration?.remove()
    }
}

// MARK: - AmenKnowledgeThreadRepository

@MainActor
final class AmenKnowledgeThreadRepository: ObservableObject {
    @Published private(set) var threads: [AmenKnowledgeThread] = []
    @Published private(set) var isLoading = false

    private let db = Firestore.firestore()
    private var listenerRegistration: ListenerRegistration?

    func startListening(uid: String) {
        guard listenerRegistration == nil else { return }
        isLoading = true

        listenerRegistration = db
            .collection("users").document(uid)
            .collection("knowledgeThreads")
            .order(by: "updatedAt", descending: true)
            .limit(to: 30)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                self.isLoading = false
                self.threads = snapshot?.documents.compactMap {
                    try? $0.data(as: AmenKnowledgeThread.self)
                } ?? []
            }
    }

    func stopListening() {
        listenerRegistration?.remove()
        listenerRegistration = nil
    }

    deinit {
        listenerRegistration?.remove()
    }
}
