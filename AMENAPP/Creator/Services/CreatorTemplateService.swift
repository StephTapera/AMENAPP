import Foundation
import FirebaseAuth
import FirebaseFirestore

protocol CreatorTemplateServicing {
    func fetchTemplates(projectType: CreatorProjectType?) async throws -> [CreatorTemplate]
    func saveTemplate(_ template: CreatorTemplate, ownerID: String) async throws
}

final class CreatorTemplateService: CreatorTemplateServicing {
    private lazy var db = Firestore.firestore()

    func fetchTemplates(projectType: CreatorProjectType?) async throws -> [CreatorTemplate] {
        var query: Query = db.collection("creatorTemplates")
        if let projectType {
            query = query.whereField("projectType", isEqualTo: projectType.rawValue)
        }
        let snapshot = try await query.getDocuments()
        return snapshot.documents.compactMap { document in
            guard let data = document.data() as [String: Any]? else { return nil }
            return try? CreatorFirestoreCoder.decode(CreatorTemplate.self, from: data)
        }
    }

    func saveTemplate(_ template: CreatorTemplate, ownerID: String) async throws {
        let ref = db.collection("users")
            .document(ownerID)
            .collection("creatorTemplatesSaved")
            .document(template.id)
        let data = try CreatorFirestoreCoder.encode(template)
        try await ref.setData(data)
    }
}
