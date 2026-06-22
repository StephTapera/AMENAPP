// AmenCreationDraftStore.swift
// AMENAPP
// Local + server draft persistence for Universal Create.

import Foundation
import FirebaseAuth

@MainActor
final class AmenCreationDraftStore: ObservableObject {
    static let shared = AmenCreationDraftStore()

    private let userDefaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let functions = CloudFunctionsService.shared

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.encoder = encoder
        self.decoder = decoder
    }

    private func storageKey(ownerId: String, intent: AmenCreationIntent) -> String {
        "amen.creation.draft.\(ownerId).\(intent.rawValue)"
    }

    func loadDraft(ownerId: String, intent: AmenCreationIntent) async -> AmenCreationDraft? {
        let key = storageKey(ownerId: ownerId, intent: intent)
        if let data = userDefaults.data(forKey: key),
           let draft = try? decoder.decode(AmenCreationDraft.self, from: data) {
            AMENAnalyticsService.shared.track(.draftRestored(type: draft.contentType.rawValue))
            return draft
        }

        // Attempt remote restore if local draft missing.
        do {
            let response = try await functions.call("getContentDraft", data: ["draftType": intent.rawValue])
            if let payload = response as? [String: Any],
               let draftPayload = payload["draft"] as? [String: Any],
               let draft = decodeDraft(from: draftPayload) {
                saveLocalDraft(draft)
                AMENAnalyticsService.shared.track(.draftRestored(type: draft.contentType.rawValue))
                return draft
            }
        } catch {
            dlog("[AmenCreationDraftStore] Remote draft restore failed: \(error)")
        }

        return nil
    }

    func saveDraft(_ draft: AmenCreationDraft) async {
        saveLocalDraft(draft)
        AMENAnalyticsService.shared.track(.draftSaved(type: draft.contentType.rawValue))

        guard Auth.auth().currentUser != nil else { return }

        do {
            _ = try await functions.call("saveContentDraft", data: [
                "draftId": draft.id,
                "draftType": draft.intent.rawValue,
                "contentType": draft.contentType.rawValue,
                "title": draft.title as Any,
                "text": draft.text,
                "blocks": draft.blocks.compactMap(encodeToDictionary),
                "mediaRefs": draft.mediaRefs.compactMap(encodeToDictionary),
                "intendedVisibility": draft.intendedVisibility.rawValue,
                "publishTarget": draft.publishTarget as Any,
                "syncState": draft.syncState.rawValue
            ])
        } catch {
            dlog("[AmenCreationDraftStore] Remote draft save failed: \(error)")
        }
    }

    func deleteDraft(_ draft: AmenCreationDraft) async {
        let key = storageKey(ownerId: draft.ownerId, intent: draft.intent)
        userDefaults.removeObject(forKey: key)
        AMENAnalyticsService.shared.track(.draftDeleted(type: draft.contentType.rawValue))

        guard Auth.auth().currentUser != nil else { return }
        do {
            _ = try await functions.call("deleteContentDraft", data: ["draftId": draft.id])
        } catch {
            dlog("[AmenCreationDraftStore] Remote draft delete failed: \(error)")
        }
    }

    func publishDraft(_ draft: AmenCreationDraft) async throws -> ContentNode {
        guard Auth.auth().currentUser != nil else {
            throw NSError(domain: "AmenCreationDraftStore", code: 401, userInfo: [NSLocalizedDescriptionKey: "Auth required"])
        }

        let payload: [String: Any] = [
            "draftId": draft.id,
            "draftType": draft.intent.rawValue,
            "contentType": draft.contentType.rawValue,
            "intendedVisibility": draft.intendedVisibility.rawValue
        ]

        let result = try await functions.call("publishDraftToContentNode", data: payload)
        AMENAnalyticsService.shared.track(.draftPublished(type: draft.contentType.rawValue))

        if let response = result as? [String: Any],
           let contentId = response["contentId"] as? String {
            return draft.toContentNode().withId(contentId)
        }

        return draft.toContentNode()
    }

    private func saveLocalDraft(_ draft: AmenCreationDraft) {
        let key = storageKey(ownerId: draft.ownerId, intent: draft.intent)
        if let data = try? encoder.encode(draft) {
            userDefaults.set(data, forKey: key)
        }
    }

    private func encodeToDictionary<T: Encodable>(_ value: T) -> [String: Any]? {
        guard let data = try? encoder.encode(value),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private func decodeDraft(from payload: [String: Any]) -> AmenCreationDraft? {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let draft = try? decoder.decode(AmenCreationDraft.self, from: data) else {
            return nil
        }
        return draft
    }
}

private extension ContentNode {
    func withId(_ newId: String) -> ContentNode {
        var copy = self
        copy.id = newId
        return copy
    }
}
