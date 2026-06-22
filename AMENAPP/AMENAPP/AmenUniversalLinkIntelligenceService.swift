import Foundation
import FirebaseFunctions

struct AmenGeneratedLinkNotesDraft: Equatable {
    let title: String
    let sourceAttribution: String
    let outline: [String]
    let scriptureReferences: [String]
    let userConfirmationRequired: Bool
}

@MainActor
final class AmenUniversalLinkIntelligenceService {
    static let shared = AmenUniversalLinkIntelligenceService()
    private let functions = Functions.functions()

    private init() {}

    func generateNotes(for attachment: AmenSmartAttachment) async throws -> AmenGeneratedLinkNotesDraft {
        let payload: [String: Any] = [
            "url": attachment.canonicalUrl,
            "linkId": attachment.id,
        ]
        let result = try await functions.httpsCallable("generateUniversalLinkNotes").call(payload)
        guard let data = result.data as? [String: Any] else {
            throw AmenAttachmentError.resolveFailed
        }
        let outline = (data["outline"] as? [String]) ?? []
        return AmenGeneratedLinkNotesDraft(
            title: (data["title"] as? String) ?? attachment.title,
            sourceAttribution: (data["sourceAttribution"] as? String) ?? attachment.canonicalUrl,
            outline: outline,
            scriptureReferences: (data["scriptureReferences"] as? [String]) ?? [],
            userConfirmationRequired: (data["userConfirmationRequired"] as? Bool) ?? true
        )
    }

    func saveUniversalLink(linkId: String) async throws {
        _ = try await functions.httpsCallable("saveUniversalLink").call(["linkId": linkId])
    }
}
