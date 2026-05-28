import Foundation
import FirebaseAuth
import FirebaseFunctions
import FirebaseFirestore

struct SharePermissionResolution: Equatable {
    let canShare: Bool
    let resolvedVisibility: ShareEntityVisibility
    let externalShareAllowed: Bool
    let failureReason: String?
}

struct ReminderPayload: Equatable {
    let title: String
    let note: String
    let fireDate: Date
    let deepLink: URL?
}

struct SharePayloadResponse: Equatable {
    let text: String
    let deepLink: URL
    let webFallback: URL?
    let previewTitle: String
    let previewSubtitle: String
}

struct StoryCardResponse: Equatable {
    let deepLink: URL
    let caption: String
}

struct ShareAnalyticsEnvelope {
    let actionType: String
    let destinationType: String?
    let entityId: String
    let entityType: String
    let sourceSurface: String
    let targetType: String?
    let targetId: String?
    let smartContextEnabled: Bool
    let sessionId: String
    let latencyMs: Int?
    let failureReason: String?
}

@MainActor
final class SmartShareBackendService {
    static let shared = SmartShareBackendService()

    private let functions = Functions.functions()
    private let db = Firestore.firestore()

    func getSmartShareTargets(
        entity: ShareableEntity,
        query: String,
        filter: ShareFilterChip,
        smartContextEnabled: Bool
    ) async throws -> [SmartShareTarget] {
        let result = try await functions.httpsCallable("getSmartShareTargets").call([
            "entity": shareEntityPayload(entity),
            "query": query,
            "filter": filter.rawValue,
            "smartContextEnabled": smartContextEnabled
        ])

        guard
            let data = result.data as? [String: Any],
            let rawTargets = data["targets"] as? [[String: Any]]
        else {
            return []
        }

        return rawTargets.compactMap { raw in
            guard
                let id = raw["id"] as? String,
                let targetType = ShareTargetType(rawValue: raw["targetType"] as? String ?? ""),
                let displayName = raw["displayName"] as? String
            else {
                return nil
            }

            return SmartShareTarget(
                id: id,
                type: targetType,
                title: displayName,
                subtitle: raw["subtitle"] as? String ?? "",
                imageURL: (raw["photoURL"] as? String).flatMap(URL.init),
                badge: raw["badgeReason"] as? String,
                score: raw["score"] as? Double ?? 0,
                reasons: raw["reasons"] as? [String] ?? [],
                isOnline: raw["isOnline"] as? Bool ?? false,
                conversation: nil,
                user: nil
            )
        }
    }

    func enforceSharePermissions(
        entity: ShareableEntity,
        intent: ShareIntent,
        destination: ShareDestinationType?,
        targetId: String?
    ) async throws -> SharePermissionResolution {
        let result = try await functions.httpsCallable("enforceSharePermissions").call([
            "entity": shareEntityPayload(entity),
            "intent": intent.rawValue,
            "destinationType": destination?.rawValue as Any,
            "targetId": targetId as Any
        ])

        let data = result.data as? [String: Any] ?? [:]
        return SharePermissionResolution(
            canShare: data["canShare"] as? Bool ?? false,
            resolvedVisibility: ShareEntityVisibility(rawValue: data["resolvedVisibility"] as? String ?? "") ?? entity.visibility,
            externalShareAllowed: data["externalShareAllowed"] as? Bool ?? entity.externallyShareable,
            failureReason: data["failureReason"] as? String
        )
    }

    func createSharePayload(
        entity: ShareableEntity,
        intent: ShareIntent,
        options: ShareContextOptions,
        smartContextEnabled: Bool,
        noteText: String
    ) async throws -> SharePayloadResponse {
        let result = try await functions.httpsCallable("createSharePayload").call([
            "entity": shareEntityPayload(entity),
            "intent": intent.rawValue,
            "options": shareOptionsPayload(options),
            "smartContextEnabled": smartContextEnabled,
            "noteText": noteText
        ])

        let data = result.data as? [String: Any] ?? [:]
        guard
            let text = data["text"] as? String,
            let deepLinkString = data["deepLink"] as? String,
            let deepLink = URL(string: deepLinkString)
        else {
            throw NSError(domain: "SmartShareBackend", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid share payload response"])
        }

        return SharePayloadResponse(
            text: text,
            deepLink: deepLink,
            webFallback: (data["webFallback"] as? String).flatMap(URL.init(string:)),
            previewTitle: data["previewTitle"] as? String ?? entity.title,
            previewSubtitle: data["previewSubtitle"] as? String ?? entity.previewText
        )
    }

    func generateDeepLink(for entity: ShareableEntity) async throws -> URL {
        let result = try await functions.httpsCallable("generateDeepLink").call([
            "entity": shareEntityPayload(entity)
        ])
        let data = result.data as? [String: Any] ?? [:]
        guard let deepLink = (data["deepLink"] as? String).flatMap(URL.init(string:)) else {
            throw NSError(domain: "SmartShareBackend", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid deep link response"])
        }
        return deepLink
    }

    func moderateShareNote(_ note: String, entity: ShareableEntity) async throws -> String {
        let result = try await functions.httpsCallable("moderateShareNote").call([
            "entity": shareEntityPayload(entity),
            "noteText": note
        ])
        let data = result.data as? [String: Any] ?? [:]
        return data["sanitizedText"] as? String ?? note
    }

    func saveToNotes(entity: ShareableEntity, sourceSurface: String) async throws {
        _ = try await functions.httpsCallable("saveToNotes").call([
            "entity": shareEntityPayload(entity),
            "sourceSurface": sourceSurface
        ])
    }

    func createReminderPayload(entity: ShareableEntity, intent: ShareIntent) async throws -> ReminderPayload {
        let result = try await functions.httpsCallable("createReminderPayload").call([
            "entity": shareEntityPayload(entity),
            "intent": intent.rawValue
        ])
        let data = result.data as? [String: Any] ?? [:]
        let fireDate = (data["fireDate"] as? Timestamp)?.dateValue() ?? Date().addingTimeInterval(60 * 60 * 8)
        return ReminderPayload(
            title: data["title"] as? String ?? entity.title,
            note: data["note"] as? String ?? entity.previewText,
            fireDate: fireDate,
            deepLink: (data["deepLink"] as? String).flatMap(URL.init(string:))
        )
    }

    func generateStoryCard(entity: ShareableEntity) async throws -> StoryCardResponse {
        let result = try await functions.httpsCallable("generateStoryCard").call([
            "entity": shareEntityPayload(entity)
        ])
        let data = result.data as? [String: Any] ?? [:]
        return StoryCardResponse(
            deepLink: (data["deepLink"] as? String).flatMap(URL.init(string:)) ?? URL(string: "amen://\(entity.route.path)") ?? URL(string: "amen://home")!,
            caption: data["caption"] as? String ?? entity.title
        )
    }

    func createChurchNotePreview(entity: ShareableEntity) async throws -> String {
        let result = try await functions.httpsCallable("createChurchNotePreview").call([
            "entity": shareEntityPayload(entity)
        ])
        let data = result.data as? [String: Any] ?? [:]
        return data["previewText"] as? String ?? entity.previewText
    }

    func notifyRecipients(
        entity: ShareableEntity,
        targetId: String,
        targetType: ShareTargetType,
        previewText: String
    ) async throws {
        _ = try await functions.httpsCallable("notifyRecipients").call([
            "entity": shareEntityPayload(entity),
            "targetId": targetId,
            "targetType": targetType.rawValue,
            "previewText": previewText
        ])
    }

    func trackShareEvent(_ event: ShareAnalyticsEnvelope) async {
        do {
            _ = try await functions.httpsCallable("trackShareEvent").call([
                "actionType": event.actionType,
                "destinationType": event.destinationType as Any,
                "entityId": event.entityId,
                "entityType": event.entityType,
                "sourceSurface": event.sourceSurface,
                "targetType": event.targetType as Any,
                "targetId": event.targetId as Any,
                "smartContextEnabled": event.smartContextEnabled,
                "sessionId": event.sessionId,
                "latencyMs": event.latencyMs as Any,
                "failureReason": event.failureReason as Any
            ])
        } catch {
            try? await db.collection("shareEvents")
                .document()
                .setData([
                    "actionType": event.actionType,
                    "destinationType": event.destinationType as Any,
                    "entityId": event.entityId,
                    "entityType": event.entityType,
                    "sourceSurface": event.sourceSurface,
                    "targetType": event.targetType as Any,
                    "targetId": event.targetId as Any,
                    "smartContextEnabled": event.smartContextEnabled,
                    "sessionId": event.sessionId,
                    "latencyMs": event.latencyMs as Any,
                    "failureReason": event.failureReason as Any,
                    "actorId": Auth.auth().currentUser?.uid as Any,
                    "createdAt": FieldValue.serverTimestamp()
                ])
        }
    }

    private func shareEntityPayload(_ entity: ShareableEntity) -> [String: Any] {
        [
            "id": entity.id,
            "entityType": entity.entityType.rawValue,
            "authorId": entity.authorId,
            "authorName": entity.authorName,
            "authorUsername": entity.authorUsername as Any,
            "visibility": entity.visibility.rawValue,
            "title": entity.title,
            "previewText": entity.previewText,
            "mediaPreviewURL": entity.mediaPreviewURL as Any,
            "routePath": entity.route.path,
            "webFallbackPath": entity.route.webFallbackPath,
            "externallyShareable": entity.externallyShareable,
            "attributionPolicy": entity.attributionPolicy.rawValue,
            "sourceSurface": entity.sourceSurface,
            "linkedPostId": entity.linkedPostId as Any,
            "linkedChurchNoteId": entity.linkedChurchNoteId as Any,
            "churchId": entity.churchId as Any,
            "churchName": entity.churchName as Any,
            "groupId": entity.groupId as Any,
            "prayerCircleId": entity.prayerCircleId as Any,
            "verseReference": entity.verseReference as Any
        ]
    }

    private func shareOptionsPayload(_ options: ShareContextOptions) -> [String: Any] {
        [
            "includeCaption": options.includeCaption,
            "includeVerseCard": options.includeVerseCard,
            "includeAttribution": options.includeAttribution,
            "includeLinkPreview": options.includeLinkPreview,
            "sharePrivately": options.sharePrivately,
            "notifyRecipient": options.notifyRecipient,
            "addNoteBeforeSending": options.addNoteBeforeSending
        ]
    }
}
