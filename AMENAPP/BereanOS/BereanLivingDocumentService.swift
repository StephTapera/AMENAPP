import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - BereanLivingDocumentService

@MainActor
final class BereanLivingDocumentService: ObservableObject {
    static let shared = BereanLivingDocumentService()

    @Published private(set) var documents: [BereanLivingDocument] = []

    private let db = Firestore.firestore()
    private let maxVersionHistory = 20

    private init() {}

    // MARK: - Create

    func createDocument(
        title: String,
        type: BereanDocumentType,
        body: String,
        projectId: String
    ) async throws -> BereanLivingDocument {
        guard AMENFeatureFlags.shared.bereanOSLivingDocumentsEnabled else {
            throw BereanDocumentError.featureDisabled
        }
        guard let uid = Auth.auth().currentUser?.uid else {
            throw BereanDocumentError.unauthenticated
        }

        let id = db.collection("_").document().documentID
        let now = Date()
        let doc = BereanLivingDocument(
            id: id,
            projectId: projectId,
            ownerUid: uid,
            title: title,
            documentType: type,
            body: body,
            version: 1,
            versionHistory: [],
            sources: [],
            isPublished: false,
            createdAt: now,
            updatedAt: now
        )

        let path = BereanOSFirestore.document(uid: uid, projectId: projectId, docId: id)
        try await db.document(path).setData(encodedDocument(doc))

        documents.append(doc)
        return doc
    }

    // MARK: - Update

    func updateDocument(
        id: String,
        body: String,
        projectId: String,
        changeNotes: String
    ) async throws {
        guard AMENFeatureFlags.shared.bereanOSLivingDocumentsEnabled else {
            throw BereanDocumentError.featureDisabled
        }
        guard let uid = Auth.auth().currentUser?.uid else {
            throw BereanDocumentError.unauthenticated
        }

        let path = BereanOSFirestore.document(uid: uid, projectId: projectId, docId: id)
        let docRef = db.document(path)
        let snapshot = try await docRef.getDocument()

        guard snapshot.exists, let data = snapshot.data() else {
            throw BereanDocumentError.notFound
        }

        let existing = try decodeDocument(from: data)
        let now = Date()

        // Build a version entry from the old state
        let historyEntry = BereanDocumentVersion(
            id: db.collection("_").document().documentID,
            versionNumber: existing.version,
            body: existing.body,
            changedBy: uid,
            changedAt: existing.updatedAt,
            changeNotes: changeNotes
        )

        // Prepend and keep at most maxVersionHistory entries
        var newHistory = [historyEntry] + existing.versionHistory
        if newHistory.count > maxVersionHistory {
            newHistory = Array(newHistory.prefix(maxVersionHistory))
        }

        let encodedHistory = newHistory.map { v -> [String: Any] in
            [
                "id": v.id,
                "versionNumber": v.versionNumber,
                "body": v.body,
                "changedBy": v.changedBy,
                "changedAt": Timestamp(date: v.changedAt),
                "changeNotes": v.changeNotes
            ]
        }

        try await docRef.updateData([
            "body": body,
            "version": existing.version + 1,
            "versionHistory": encodedHistory,
            "updatedAt": Timestamp(date: now)
        ])

        if let idx = documents.firstIndex(where: { $0.id == id }) {
            var updated = documents[idx]
            updated = BereanLivingDocument(
                id: updated.id,
                projectId: updated.projectId,
                ownerUid: updated.ownerUid,
                title: updated.title,
                documentType: updated.documentType,
                body: body,
                version: existing.version + 1,
                versionHistory: newHistory,
                sources: updated.sources,
                isPublished: updated.isPublished,
                createdAt: updated.createdAt,
                updatedAt: now
            )
            documents[idx] = updated
        }
    }

    // MARK: - Fetch

    func fetchDocuments(projectId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw BereanDocumentError.unauthenticated
        }

        let path = BereanOSFirestore.documents(uid: uid, projectId: projectId)
        let snapshot = try await db.collection(path)
            .order(by: "updatedAt", descending: true)
            .getDocuments()

        documents = snapshot.documents.compactMap { snap in
            try? decodeDocument(from: snap.data())
        }
    }

    func fetchVersionHistory(docId: String, projectId: String) async throws -> [BereanDocumentVersion] {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw BereanDocumentError.unauthenticated
        }

        let path = BereanOSFirestore.document(uid: uid, projectId: projectId, docId: docId)
        let snapshot = try await db.document(path).getDocument()

        guard snapshot.exists, let data = snapshot.data() else {
            throw BereanDocumentError.notFound
        }

        let doc = try decodeDocument(from: data)
        return doc.versionHistory
    }

    // MARK: - Publish Toggle

    func togglePublish(docId: String, projectId: String) async throws {
        guard AMENFeatureFlags.shared.bereanOSLivingDocumentsEnabled else {
            throw BereanDocumentError.featureDisabled
        }
        guard let uid = Auth.auth().currentUser?.uid else {
            throw BereanDocumentError.unauthenticated
        }

        guard let idx = documents.firstIndex(where: { $0.id == docId }) else {
            throw BereanDocumentError.notFound
        }

        let current = documents[idx]
        let newPublished = !current.isPublished

        let path = BereanOSFirestore.document(uid: uid, projectId: projectId, docId: docId)
        try await db.document(path).updateData(["isPublished": newPublished])

        let updated = BereanLivingDocument(
            id: current.id,
            projectId: current.projectId,
            ownerUid: current.ownerUid,
            title: current.title,
            documentType: current.documentType,
            body: current.body,
            version: current.version,
            versionHistory: current.versionHistory,
            sources: current.sources,
            isPublished: newPublished,
            createdAt: current.createdAt,
            updatedAt: Date()
        )
        documents[idx] = updated
    }

    // MARK: - Helpers

    private func encodedDocument(_ doc: BereanLivingDocument) -> [String: Any] {
        [
            "id": doc.id,
            "projectId": doc.projectId,
            "ownerUid": doc.ownerUid,
            "title": doc.title,
            "documentType": doc.documentType.rawValue,
            "body": doc.body,
            "version": doc.version,
            "versionHistory": doc.versionHistory.map { v -> [String: Any] in
                [
                    "id": v.id,
                    "versionNumber": v.versionNumber,
                    "body": v.body,
                    "changedBy": v.changedBy,
                    "changedAt": Timestamp(date: v.changedAt),
                    "changeNotes": v.changeNotes
                ]
            },
            "sources": doc.sources,
            "isPublished": doc.isPublished,
            "createdAt": Timestamp(date: doc.createdAt),
            "updatedAt": Timestamp(date: doc.updatedAt)
        ]
    }

    private func decodeDocument(from data: [String: Any]) throws -> BereanLivingDocument {
        guard
            let id = data["id"] as? String,
            let projectId = data["projectId"] as? String,
            let ownerUid = data["ownerUid"] as? String,
            let title = data["title"] as? String,
            let documentTypeRaw = data["documentType"] as? String,
            let documentType = BereanDocumentType(rawValue: documentTypeRaw),
            let body = data["body"] as? String,
            let version = data["version"] as? Int,
            let isPublished = data["isPublished"] as? Bool,
            let createdAtTs = data["createdAt"] as? Timestamp,
            let updatedAtTs = data["updatedAt"] as? Timestamp
        else {
            throw BereanDocumentError.decodingFailed
        }

        let historyData = data["versionHistory"] as? [[String: Any]] ?? []
        let versionHistory: [BereanDocumentVersion] = historyData.compactMap { v in
            guard
                let hId = v["id"] as? String,
                let vNum = v["versionNumber"] as? Int,
                let hBody = v["body"] as? String,
                let changedBy = v["changedBy"] as? String,
                let changedAtTs = v["changedAt"] as? Timestamp,
                let changeNotes = v["changeNotes"] as? String
            else { return nil }
            return BereanDocumentVersion(
                id: hId,
                versionNumber: vNum,
                body: hBody,
                changedBy: changedBy,
                changedAt: changedAtTs.dateValue(),
                changeNotes: changeNotes
            )
        }

        let sources = data["sources"] as? [String] ?? []

        return BereanLivingDocument(
            id: id,
            projectId: projectId,
            ownerUid: ownerUid,
            title: title,
            documentType: documentType,
            body: body,
            version: version,
            versionHistory: versionHistory,
            sources: sources,
            isPublished: isPublished,
            createdAt: createdAtTs.dateValue(),
            updatedAt: updatedAtTs.dateValue()
        )
    }
}

// MARK: - Errors

enum BereanDocumentError: LocalizedError {
    case featureDisabled
    case unauthenticated
    case notFound
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .featureDisabled: return "Living documents feature is not currently enabled."
        case .unauthenticated: return "You must be signed in to manage documents."
        case .notFound: return "Document not found."
        case .decodingFailed: return "Unable to read document data."
        }
    }
}
