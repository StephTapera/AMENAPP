import Foundation
import FirebaseAuth
import FirebaseFunctions

struct NoteShareSuggestedAction: Identifiable, Equatable {
    let id: String
    let label: String
    let systemIcon: String
    let intent: String
}

struct NoteShareSnapshotBlock: Identifiable, Equatable {
    let id: String
    let text: String
    let semanticType: String
    let blockType: String
    let scriptureReference: String?
}

struct NoteShareViewerSnapshot: Equatable {
    let title: String
    let sermonTitle: String?
    let sermonSpeaker: String?
    let churchName: String?
    let scriptureReferences: [String]
    let excerpt: String
    let blocks: [NoteShareSnapshotBlock]
}

struct NoteShareViewerPayload: Identifiable, Equatable {
    let id: String
    let noteId: String
    let status: String
    let appPath: String
    let webFallbackPath: String
    let snapshot: NoteShareViewerSnapshot
    let suggestedActions: [NoteShareSuggestedAction]
    let summary: String
    let viewerCanOpenSourceNote: Bool
    let viewerCanSeeFullSnapshot: Bool
}

struct NoteShareCreateResult: Equatable {
    let shareId: String
    let linkToken: String?
    let appPath: String
    let webFallbackPath: String
    let suggestedActions: [NoteShareSuggestedAction]
}

@MainActor
protocol NoteShareServing {
    func createShare(
        noteId: String,
        selectedBlockIds: [String],
        accessPolicy: NoteShareAccessPolicy
    ) async throws -> NoteShareCreateResult
    func viewerPayload(shareId: String, linkToken: String?) async throws -> NoteShareViewerPayload
    func toggleAmen(shareId: String, linkToken: String?) async throws -> Bool
    func addReflection(shareId: String, body: String, linkToken: String?) async throws
    func revoke(shareId: String) async throws
}

@MainActor
final class NoteShareService: NoteShareServing {
    static let shared = NoteShareService()

    private let functions = Functions.functions(region: "us-central1")

    private init() {}

    func createShare(
        noteId: String,
        selectedBlockIds: [String] = [],
        accessPolicy: NoteShareAccessPolicy = NoteShareAccessPolicy(
            audience: .ownerOnly,
            signedOutAccess: .denied,
            followerPolicy: .disabled,
            requiresAuth: true,
            allowExternalIndexing: false
        )
    ) async throws -> NoteShareCreateResult {
        let payload: [String: Any] = [
            "noteId": noteId,
            "selectedBlockIds": selectedBlockIds,
            "shareConfig": accessPolicy.noteShareConfigValue,
            "renderMode": "selah",
        ]
        let result = try await functions.httpsCallable("noteShareCreate").call(payload)
        guard let data = result.data as? [String: Any] else {
            throw NoteShareServiceError.invalidResponse
        }
        return try parseCreateResult(data)
    }

    func viewerPayload(shareId: String, linkToken: String? = nil) async throws -> NoteShareViewerPayload {
        var payload: [String: Any] = ["shareId": shareId]
        if let linkToken { payload["linkToken"] = linkToken }
        let result = try await functions.httpsCallable("noteShareGetViewerPayload").call(payload)
        guard let data = result.data as? [String: Any] else {
            throw NoteShareServiceError.invalidResponse
        }
        return try parseViewerPayload(data)
    }

    func toggleAmen(shareId: String, linkToken: String? = nil) async throws -> Bool {
        var payload: [String: Any] = ["shareId": shareId]
        if let linkToken { payload["linkToken"] = linkToken }
        let result = try await functions.httpsCallable("noteShareToggleAmen").call(payload)
        guard let data = result.data as? [String: Any], let amened = data["amened"] as? Bool else {
            throw NoteShareServiceError.invalidResponse
        }
        return amened
    }

    func addReflection(shareId: String, body: String, linkToken: String? = nil) async throws {
        var payload: [String: Any] = ["shareId": shareId, "body": body]
        if let linkToken { payload["linkToken"] = linkToken }
        _ = try await functions.httpsCallable("noteShareAddReflection").call(payload)
    }

    func revoke(shareId: String) async throws {
        _ = try await functions.httpsCallable("noteShareRevoke").call(["shareId": shareId])
    }

    private func parseCreateResult(_ data: [String: Any]) throws -> NoteShareCreateResult {
        guard let shareId = data["shareId"] as? String else { throw NoteShareServiceError.invalidResponse }
        let route = data["route"] as? [String: Any]
        return NoteShareCreateResult(
            shareId: shareId,
            linkToken: data["linkToken"] as? String,
            appPath: route?["appPath"] as? String ?? "amen://note-share/\(shareId)",
            webFallbackPath: route?["webFallbackPath"] as? String ?? "https://amenapp.com/note-share/\(shareId)",
            suggestedActions: []
        )
    }

    func parseViewerPayload(_ data: [String: Any]) throws -> NoteShareViewerPayload {
        guard let shareId = data["shareId"] as? String,
              let noteId = data["noteId"] as? String
        else { throw NoteShareServiceError.invalidResponse }

        let blocks = (data["renderBlocks"] as? [[String: Any]] ?? []).compactMap { block -> NoteShareSnapshotBlock? in
            guard let id = block["id"] as? String else { return nil }
            return NoteShareSnapshotBlock(
                id: id,
                text: block["text"] as? String ?? "",
                semanticType: block["semanticType"] as? String ?? "general",
                blockType: block["kind"] as? String ?? "paragraph",
                scriptureReference: block["scriptureReference"] as? String
            )
        }
        let route = data["route"] as? [String: Any]
        let title = data["title"] as? String ?? "Church Note"
        let excerpt = data["summary"] as? String ?? data["subtitle"] as? String ?? blocks.first?.text ?? ""
        let snapshot = NoteShareViewerSnapshot(
            title: title,
            sermonTitle: data["subtitle"] as? String,
            sermonSpeaker: data["sermonSpeaker"] as? String,
            churchName: data["churchName"] as? String ?? data["eyebrow"] as? String,
            scriptureReferences: data["scriptureRefs"] as? [String] ?? [],
            excerpt: excerpt,
            blocks: blocks
        )

        return NoteShareViewerPayload(
            id: shareId,
            noteId: noteId,
            status: data["status"] as? String ?? "active",
            appPath: route?["appPath"] as? String ?? "amen://note-share/\(shareId)",
            webFallbackPath: route?["webFallbackPath"] as? String ?? "https://amenapp.com/note-share/\(shareId)",
            snapshot: snapshot,
            suggestedActions: parseActions(data["smartActions"]),
            summary: excerpt,
            viewerCanOpenSourceNote: data["viewerCanOpenSourceNote"] as? Bool ?? data["authorPanel"] != nil,
            viewerCanSeeFullSnapshot: data["viewerCanSeeFullSnapshot"] as? Bool ?? true
        )
    }

    private func parseActions(_ raw: Any?) -> [NoteShareSuggestedAction] {
        guard let rows = raw as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let id = row["id"] as? String,
                  let label = row["label"] as? String,
                  let systemIcon = row["systemIcon"] as? String,
                  let intent = row["intent"] as? String
            else { return nil }
            return NoteShareSuggestedAction(id: id, label: label, systemIcon: systemIcon, intent: intent)
        }
    }
}

enum NoteShareServiceError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The note share response could not be read."
        }
    }
}

private extension NoteShareAccessPolicy {
    var noteShareConfigValue: [String: Any] {
        let visibility: String
        switch audience {
        case .publicLink:
            visibility = "link"
        case .followers:
            visibility = "followers"
        case .church:
            visibility = "church"
        case .collaborators, .ownerOnly:
            visibility = "link"
        }
        return [
            "visibility": visibility,
            "allowAmens": true,
            "allowComments": "everyone",
            "allowReshare": false,
            "showCounts": false,
            "authorPrivateAmenList": true,
            "attribution": "full",
            "watermarkOnExport": true,
        ]
    }
}
