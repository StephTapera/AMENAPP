import Foundation
import FirebaseAuth
import FirebaseFunctions

@MainActor
final class ActionIntelligenceService: ObservableObject {
    static let shared = ActionIntelligenceService()

    private let functions = Functions.functions(region: "us-central1")

    private init() {}

    func execute(
        action: AmenActionSuggestion,
        analysis: AmenIntentAnalysis?,
        source: ActionIntelligenceSourcePayload
    ) async throws -> ActionIntelligenceExecutionResult {
        guard Auth.auth().currentUser?.uid != nil else {
            throw ActionIntelligenceServiceError.unauthenticated
        }

        var payload: [String: Any] = [
            "actionVerb": action.verb.rawValue,
            "source": source.dictionaryValue
        ]
        if let analysis {
            payload["analysis"] = analysis.callablePayload
        }

        let result = try await functions.httpsCallable("executeAmenAction").call(payload)
        guard let data = result.data as? [String: Any] else {
            throw ActionIntelligenceServiceError.invalidResponse
        }
        return ActionIntelligenceExecutionResult(data: data)
    }
}

enum ActionIntelligenceServiceError: LocalizedError {
    case unauthenticated
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unauthenticated:
            return "Sign in to use Amen actions."
        case .invalidResponse:
            return "Amen Action Intelligence returned an unexpected response."
        }
    }
}

struct ActionIntelligenceSourcePayload {
    let sourceId: String
    let sourceType: String
    let sourceText: String
    let conversationId: String?
    let roomId: String?
    let postId: String?
    let commentId: String?
    let churchId: String?
    let spaceId: String?
    let organizationId: String?
    let authorId: String?
    let targetUserId: String?
    let targetDisplayName: String?
    let title: String?
    let dueAt: Date?
    let locationName: String?
    let scriptureReference: String?
    let resourceUrl: String?

    init(
        sourceId: String,
        sourceType: String,
        sourceText: String,
        conversationId: String? = nil,
        roomId: String? = nil,
        postId: String? = nil,
        commentId: String? = nil,
        churchId: String? = nil,
        spaceId: String? = nil,
        organizationId: String? = nil,
        authorId: String? = nil,
        targetUserId: String? = nil,
        targetDisplayName: String? = nil,
        title: String? = nil,
        dueAt: Date? = nil,
        locationName: String? = nil,
        scriptureReference: String? = nil,
        resourceUrl: String? = nil
    ) {
        self.sourceId = sourceId
        self.sourceType = sourceType
        self.sourceText = sourceText
        self.conversationId = conversationId
        self.roomId = roomId
        self.postId = postId
        self.commentId = commentId
        self.churchId = churchId
        self.spaceId = spaceId
        self.organizationId = organizationId
        self.authorId = authorId
        self.targetUserId = targetUserId
        self.targetDisplayName = targetDisplayName
        self.title = title
        self.dueAt = dueAt
        self.locationName = locationName
        self.scriptureReference = scriptureReference
        self.resourceUrl = resourceUrl
    }

    var dictionaryValue: [String: Any] {
        var value: [String: Any] = [
            "sourceId": sourceId,
            "sourceType": sourceType,
            "sourceText": sourceText
        ]
        value.addIfPresent(conversationId, forKey: "conversationId")
        value.addIfPresent(roomId, forKey: "roomId")
        value.addIfPresent(postId, forKey: "postId")
        value.addIfPresent(commentId, forKey: "commentId")
        value.addIfPresent(churchId, forKey: "churchId")
        value.addIfPresent(spaceId, forKey: "spaceId")
        value.addIfPresent(organizationId, forKey: "organizationId")
        value.addIfPresent(authorId, forKey: "authorId")
        value.addIfPresent(targetUserId, forKey: "targetUserId")
        value.addIfPresent(targetDisplayName, forKey: "targetDisplayName")
        value.addIfPresent(title, forKey: "title")
        value.addIfPresent(locationName, forKey: "locationName")
        value.addIfPresent(scriptureReference, forKey: "scriptureReference")
        value.addIfPresent(resourceUrl, forKey: "resourceUrl")
        if let dueAt {
            value["dueAt"] = ISO8601DateFormatter().string(from: dueAt)
        }
        return value
    }
}

struct ActionIntelligenceExecutionResult: Equatable {
    let workflow: String
    let objectId: String?
    let successMessage: String
    let result: [String: Any]

    init(data: [String: Any]) {
        workflow = data["workflow"] as? String ?? "action_intelligence"
        objectId = data["objectId"] as? String
        successMessage = data["message"] as? String ?? "Amen action saved."
        result = data["result"] as? [String: Any] ?? [:]
    }

    static func == (lhs: ActionIntelligenceExecutionResult, rhs: ActionIntelligenceExecutionResult) -> Bool {
        lhs.workflow == rhs.workflow && lhs.objectId == rhs.objectId && lhs.successMessage == rhs.successMessage
    }
}

private extension AmenIntentAnalysis {
    var callablePayload: [String: Any] {
        [
            "id": id,
            "sourceId": sourceId,
            "surface": surface.rawValue,
            "privacyTier": privacyTier.rawValue,
            "intentKind": intentKind.rawValue,
            "objectClass": objectClass.rawValue,
            "confidence": confidence,
            "sensitivityLevel": sensitivityLevel.rawValue,
            "detectedSignals": detectedSignals,
            "explanation": explanation,
            "shouldSuppressCapsule": shouldSuppressCapsule,
            "createdAt": ISO8601DateFormatter().string(from: createdAt)
        ]
    }
}

private extension Dictionary where Key == String, Value == Any {
    mutating func addIfPresent(_ value: String?, forKey key: String) {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        self[key] = value
    }
}
