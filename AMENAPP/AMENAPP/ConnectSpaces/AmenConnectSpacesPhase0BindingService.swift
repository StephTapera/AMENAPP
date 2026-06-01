import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// MARK: - AmenConnectSpacesPhase0BindingError

enum AmenConnectSpacesPhase0BindingError: LocalizedError {
    case notAuthenticated
    case missingDocumentId
    case missingField(String)
    case invalidField(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in."
        case .missingDocumentId:
            return "Firestore document id is missing."
        case .missingField(let field):
            return "Missing required field: \(field)."
        case .invalidField(let field):
            return "Invalid field: \(field)."
        case .invalidResponse:
            return "The server response was not in the expected format."
        }
    }
}

// MARK: - Firestore Binding

struct AmenConnectSpacesFirestoreBinding {
    static let spacesCollection = "spaces"
    static let messagesSubcollection = "messages"
    static let itemsSubcollection = "items"
    static let presenceCollection = "presence"
    static let connectVideosCollection = "connectVideos"
    static let commentsSubcollection = "comments"
    static let knowledgeGraphCollection = "knowledgeGraph"
    static let aegisFlagsCollection = "aegisFlags"

    static func bindSpace(_ snapshot: DocumentSnapshot) throws -> AmenConnectSpacesSpace {
        let data = try data(from: snapshot)
        return AmenConnectSpacesSpace(
            id: snapshot.documentID,
            name: try string(data, "name"),
            type: try enumValue(data, "type", as: AmenConnectSpacesRoomType.self),
            memberIds: try stringArray(data, "memberIds"),
            careSensitivity: try bool(data, "careSensitivity"),
            createdBy: try string(data, "createdBy"),
            createdAt: try date(data, "createdAt"),
            updatedAt: try date(data, "updatedAt")
        )
    }

    static func bindMessage(_ snapshot: DocumentSnapshot) throws -> AmenConnectSpacesMessage {
        let data = try data(from: snapshot)
        return AmenConnectSpacesMessage(
            id: snapshot.documentID,
            body: try string(data, "body"),
            authorId: try string(data, "authorId"),
            detectedIntents: try enumArray(data, "detectedIntents", as: AmenConnectSpacesMessageIntent.self),
            convictionCheck: try convictionCheck(data["convictionCheck"]),
            careRouted: try bool(data, "careRouted"),
            createdAt: try date(data, "createdAt"),
            updatedAt: try date(data, "updatedAt")
        )
    }

    static func bindDerivedItem(_ snapshot: DocumentSnapshot) throws -> AmenConnectSpacesDerivedItem {
        let data = try data(from: snapshot)
        return AmenConnectSpacesDerivedItem(
            id: snapshot.documentID,
            kind: try enumValue(data, "kind", as: AmenConnectSpacesDerivedItemKind.self),
            title: try string(data, "title"),
            owner: data["owner"] as? String,
            due: optionalDate(data["due"]),
            status: try enumValue(data, "status", as: AmenConnectSpacesItemStatus.self),
            sourceMsgId: try string(data, "sourceMsgId"),
            createdAt: try date(data, "createdAt"),
            updatedAt: try date(data, "updatedAt")
        )
    }

    static func bindPresence(_ snapshot: DocumentSnapshot) throws -> AmenConnectSpacesPresence {
        let data = try data(from: snapshot)
        return AmenConnectSpacesPresence(
            userId: snapshot.documentID,
            spiritualState: try enumValue(data, "spiritualState", as: AmenConnectSpacesSpiritualState.self),
            urgentReachable: try bool(data, "urgentReachable"),
            sabbathUntil: optionalDate(data["sabbathUntil"]),
            updatedAt: try date(data, "updatedAt")
        )
    }

    static func bindConnectVideo(_ snapshot: DocumentSnapshot) throws -> AmenConnectSpacesConnectVideo {
        let data = try data(from: snapshot)
        return AmenConnectSpacesConnectVideo(
            id: snapshot.documentID,
            provenance: try videoProvenance(data["provenance"]),
            teacherId: try string(data, "teacherId"),
            transcriptRef: try string(data, "transcriptRef"),
            claims: try dictionaryArray(data, "claims").map(teachingClaim),
            scriptureRefs: try dictionaryArray(data, "scriptureRefs").map(scriptureRef),
            sponsored: try bool(data, "sponsored"),
            createdAt: try date(data, "createdAt"),
            updatedAt: try date(data, "updatedAt")
        )
    }

    static func bindConnectComment(_ snapshot: DocumentSnapshot) throws -> AmenConnectSpacesConnectComment {
        let data = try data(from: snapshot)
        return AmenConnectSpacesConnectComment(
            id: snapshot.documentID,
            type: try enumValue(data, "type", as: AmenConnectSpacesCommentType.self),
            body: try string(data, "body"),
            authorId: try string(data, "authorId"),
            edificationScore: try double(data, "edificationScore"),
            createdAt: try date(data, "createdAt")
        )
    }

    static func bindKnowledgeGraph(_ snapshot: DocumentSnapshot) throws -> AmenConnectSpacesKnowledgeGraph {
        let data = try data(from: snapshot)
        return AmenConnectSpacesKnowledgeGraph(
            userId: snapshot.documentID,
            studied: try stringArray(data, "studied"),
            understood: try stringArray(data, "understood"),
            wrestlingWith: try stringArray(data, "wrestlingWith"),
            saved: try stringArray(data, "saved"),
            nextUp: try stringArray(data, "nextUp"),
            updatedAt: try date(data, "updatedAt")
        )
    }

    static func bindAegisFlag(_ snapshot: DocumentSnapshot) throws -> AmenConnectSpacesAegisFlag {
        let data = try data(from: snapshot)
        return AmenConnectSpacesAegisFlag(
            id: snapshot.documentID,
            capabilityRef: try string(data, "capabilityRef"),
            surface: try enumValue(data, "surface", as: AmenConnectSpacesSurface.self),
            severity: try string(data, "severity"),
            action: try enumValue(data, "action", as: AmenConnectSpacesAegisAction.self),
            subjectRef: try string(data, "subjectRef"),
            createdAt: try date(data, "createdAt")
        )
    }

    static func firestorePayload<T: Encodable>(for value: T) throws -> [String: Any] {
        let encoded = try Firestore.Encoder().encode(value)
        guard let payload = encoded as? [String: Any] else {
            throw AmenConnectSpacesPhase0BindingError.invalidField("payload")
        }
        return payload
    }

    private static func data(from snapshot: DocumentSnapshot) throws -> [String: Any] {
        guard !snapshot.documentID.isEmpty else { throw AmenConnectSpacesPhase0BindingError.missingDocumentId }
        guard let data = snapshot.data() else { throw AmenConnectSpacesPhase0BindingError.invalidResponse }
        return data
    }

    private static func string(_ data: [String: Any], _ key: String) throws -> String {
        guard let value = data[key] as? String, !value.isEmpty else {
            throw AmenConnectSpacesPhase0BindingError.missingField(key)
        }
        return value
    }

    private static func bool(_ data: [String: Any], _ key: String) throws -> Bool {
        guard let value = data[key] as? Bool else { throw AmenConnectSpacesPhase0BindingError.invalidField(key) }
        return value
    }

    private static func double(_ data: [String: Any], _ key: String) throws -> Double {
        if let value = data[key] as? Double { return value }
        if let value = data[key] as? Int { return Double(value) }
        throw AmenConnectSpacesPhase0BindingError.invalidField(key)
    }

    private static func date(_ data: [String: Any], _ key: String) throws -> Date {
        guard let value = optionalDate(data[key]) else { throw AmenConnectSpacesPhase0BindingError.invalidField(key) }
        return value
    }

    private static func optionalDate(_ value: Any?) -> Date? {
        if let timestamp = value as? Timestamp { return timestamp.dateValue() }
        if let date = value as? Date { return date }
        return nil
    }

    private static func stringArray(_ data: [String: Any], _ key: String) throws -> [String] {
        guard let values = data[key] as? [String] else { throw AmenConnectSpacesPhase0BindingError.invalidField(key) }
        return values
    }

    private static func dictionaryArray(_ data: [String: Any], _ key: String) throws -> [[String: Any]] {
        guard let values = data[key] as? [[String: Any]] else { throw AmenConnectSpacesPhase0BindingError.invalidField(key) }
        return values
    }

    private static func enumValue<E: RawRepresentable>(_ data: [String: Any], _ key: String, as type: E.Type) throws -> E where E.RawValue == String {
        let raw = try string(data, key)
        guard let value = E(rawValue: raw) else { throw AmenConnectSpacesPhase0BindingError.invalidField(key) }
        return value
    }

    private static func enumArray<E: RawRepresentable>(_ data: [String: Any], _ key: String, as type: E.Type) throws -> [E] where E.RawValue == String {
        guard let rawValues = data[key] as? [String] else { throw AmenConnectSpacesPhase0BindingError.invalidField(key) }
        return try rawValues.map { rawValue in
            guard let value = E(rawValue: rawValue) else { throw AmenConnectSpacesPhase0BindingError.invalidField(key) }
            return value
        }
    }

    private static func convictionCheck(_ value: Any?) throws -> AmenConnectSpacesConvictionCheck {
        guard let data = value as? [String: Any] else { throw AmenConnectSpacesPhase0BindingError.invalidField("convictionCheck") }
        return AmenConnectSpacesConvictionCheck(
            enabled: try bool(data, "enabled"),
            suggestedPause: try bool(data, "suggestedPause"),
            warningKinds: try enumArray(data, "warningKinds", as: AmenConnectSpacesBeforeShareWarning.self),
            checkedAt: optionalDate(data["checkedAt"])
        )
    }

    private static func videoProvenance(_ value: Any?) throws -> AmenConnectSpacesVideoProvenance {
        guard let data = value as? [String: Any] else { throw AmenConnectSpacesPhase0BindingError.invalidField("provenance") }
        return AmenConnectSpacesVideoProvenance(
            humanRecorded: try bool(data, "humanRecorded"),
            aiEdited: try bool(data, "aiEdited"),
            aiGenerated: try bool(data, "aiGenerated"),
            synthVoice: try bool(data, "synthVoice"),
            synthFace: try bool(data, "synthFace"),
            deepfakeRisk: try double(data, "deepfakeRisk"),
            verifiedOriginal: try bool(data, "verifiedOriginal")
        )
    }

    private static func teachingClaim(_ data: [String: Any]) throws -> AmenConnectSpacesTeachingClaim {
        AmenConnectSpacesTeachingClaim(
            id: try string(data, "id"),
            text: try string(data, "text"),
            timestampSeconds: data["timestampSeconds"] as? TimeInterval,
            sourceTranscriptRange: data["sourceTranscriptRange"] as? String,
            opposingFaithfulViews: try stringArray(data, "opposingFaithfulViews")
        )
    }

    private static func scriptureRef(_ data: [String: Any]) throws -> AmenConnectSpacesScriptureRefProvenance {
        AmenConnectSpacesScriptureRefProvenance(
            id: try string(data, "id"),
            reference: try string(data, "reference"),
            translation: try string(data, "translation"),
            sourceLayer: try enumValue(data, "sourceLayer", as: AmenConnectSpacesScriptureProvenanceLayer.self),
            verifiedAt: try date(data, "verifiedAt"),
            confidence: try double(data, "confidence")
        )
    }
}

// MARK: - Callable Proxy

@MainActor
final class AmenConnectSpacesCallableProxy {
    static let shared = AmenConnectSpacesCallableProxy()

    private let functions: Functions

    init(functions: Functions = Functions.functions()) {
        self.functions = functions
    }

    @discardableResult
    func call(_ callable: AmenConnectSpacesCallable, payload: [String: Any] = [:], timeout: TimeInterval = 15) async throws -> [String: Any] {
        guard Auth.auth().currentUser != nil else {
            throw AmenConnectSpacesPhase0BindingError.notAuthenticated
        }
        let result = try await functions.httpsCallable(callable.rawValue).safeCall(payload, timeout: timeout)
        guard let response = result.data as? [String: Any] else {
            throw AmenConnectSpacesPhase0BindingError.invalidResponse
        }
        return response
    }

    func createMinistrySpace(name: String, type: AmenConnectSpacesRoomType, memberIds: [String], careSensitivity: Bool) async throws -> String {
        let response = try await call(.createMinistrySpace, payload: [
            "name": name,
            "type": type.rawValue,
            "memberIds": memberIds,
            "careSensitivity": careSensitivity
        ])
        return try id(response, keys: ["spaceId", "id"])
    }

    func postMinistryMessage(spaceId: String, body: String) async throws -> String {
        let response = try await call(.postMinistryMessage, payload: ["spaceId": spaceId, "body": body])
        return try id(response, keys: ["messageId", "msgId", "id"])
    }

    func detectMessageIntents(spaceId: String, messageId: String, body: String) async throws -> [AmenConnectSpacesMessageIntent] {
        let response = try await call(.detectMessageIntents, payload: ["spaceId": spaceId, "messageId": messageId, "body": body], timeout: 30)
        let rawValues = response["detectedIntents"] as? [String] ?? response["intents"] as? [String] ?? []
        return rawValues.compactMap(AmenConnectSpacesMessageIntent.init(rawValue:))
    }

    func routeCareSignal(spaceId: String, messageId: String, intents: [AmenConnectSpacesMessageIntent]) async throws -> [String: Any] {
        try await call(.routeCareSignal, payload: [
            "spaceId": spaceId,
            "messageId": messageId,
            "detectedIntents": intents.map(\.rawValue)
        ])
    }

    func updateSpiritualPresence(_ presence: AmenConnectSpacesPresence) async throws -> [String: Any] {
        try await call(.updateSpiritualPresence, payload: try AmenConnectSpacesFirestoreBinding.firestorePayload(for: presence))
    }

    func runConvictionCheck(spaceId: String, messageId: String?, body: String) async throws -> AmenConnectSpacesConvictionCheck {
        let response = try await call(.runConvictionCheck, payload: ["spaceId": spaceId, "messageId": messageId as Any, "body": body], timeout: 20)
        return try AmenConnectSpacesFirestoreBinding.bindMessageConvictionCheckPayload(response)
    }

    func runBeforeShareCheck(surface: AmenConnectSpacesSurface, body: String) async throws -> [AmenConnectSpacesBeforeShareWarning] {
        let response = try await call(.runBeforeShareCheck, payload: ["surface": surface.rawValue, "body": body], timeout: 20)
        let rawValues = response["warningKinds"] as? [String] ?? []
        return rawValues.compactMap(AmenConnectSpacesBeforeShareWarning.init(rawValue:))
    }

    func fetchConnectVideoContext(videoId: String) async throws -> [String: Any] {
        try await call(.fetchConnectVideoContext, payload: ["videoId": videoId])
    }

    func verifyScriptureProvenance(videoId: String, references: [String]) async throws -> [String: Any] {
        try await call(.verifyScriptureProvenance, payload: ["videoId": videoId, "references": references], timeout: 30)
    }

    func recordKnowledgeGraphEvent(userId: String, event: String, itemRef: String) async throws -> [String: Any] {
        try await call(.recordKnowledgeGraphEvent, payload: ["userId": userId, "event": event, "itemRef": itemRef])
    }

    func scoreEdifyingComment(videoId: String, commentId: String?, type: AmenConnectSpacesCommentType, body: String) async throws -> Double {
        let response = try await call(.scoreEdifyingComment, payload: ["videoId": videoId, "commentId": commentId as Any, "type": type.rawValue, "body": body], timeout: 20)
        return response["edificationScore"] as? Double ?? 0
    }

    func runAegisInputGate(_ request: AmenConnectSpacesAegisGateRequest) async throws -> AmenConnectSpacesAegisGateDecision {
        let response = try await call(.runAegisInputGate, payload: try AmenConnectSpacesFirestoreBinding.firestorePayload(for: request))
        return try AmenConnectSpacesAegisBinding.gateDecision(from: response)
    }

    func runAegisOutputGate(_ request: AmenConnectSpacesAegisGateRequest) async throws -> AmenConnectSpacesAegisGateDecision {
        let response = try await call(.runAegisOutputGate, payload: try AmenConnectSpacesFirestoreBinding.firestorePayload(for: request))
        return try AmenConnectSpacesAegisBinding.gateDecision(from: response)
    }

    func scanUploadForFamilySafety(uploadRef: String, surface: AmenConnectSpacesSurface) async throws -> AmenConnectSpacesAegisGateDecision {
        let response = try await call(.scanUploadForFamilySafety, payload: ["uploadRef": uploadRef, "surface": surface.rawValue], timeout: 30)
        return try AmenConnectSpacesAegisBinding.gateDecision(from: response)
    }

    func searchMinistryMemory(spaceId: String, query: String, limit: Int = 10) async throws -> [AmenConnectSpacesMinistryMemoryResult] {
        let response = try await call(.searchMinistryMemory, payload: ["spaceId": spaceId, "query": query, "limit": limit], timeout: 30)
        guard let rows = response["results"] as? [[String: Any]] else { return [] }
        return try rows.map(AmenConnectSpacesAegisBinding.ministryMemoryResult)
    }

    private func id(_ response: [String: Any], keys: [String]) throws -> String {
        for key in keys {
            if let value = response[key] as? String, !value.isEmpty { return value }
        }
        throw AmenConnectSpacesPhase0BindingError.invalidResponse
    }
}

// MARK: - Aegis Binding

struct AmenConnectSpacesAegisBinding {
    static let capabilityRefs: [String] = (1...58).map { "C\($0)" }
    static let capabilityRefSet = Set(capabilityRefs)

    static func inputGateRequest(surface: AmenConnectSpacesSurface, inputRef: String, userId: String, capabilityRefs: [String], spaceId: String? = nil, videoId: String? = nil) throws -> AmenConnectSpacesAegisGateRequest {
        try validateCapabilityRefs(capabilityRefs)
        return AmenConnectSpacesAegisGateRequest(surface: surface, capabilityRefs: capabilityRefs, inputRef: inputRef, userId: userId, spaceId: spaceId, videoId: videoId)
    }

    static func outputGateRequest(surface: AmenConnectSpacesSurface, inputRef: String, userId: String, capabilityRefs: [String], spaceId: String? = nil, videoId: String? = nil) throws -> AmenConnectSpacesAegisGateRequest {
        try validateCapabilityRefs(capabilityRefs)
        return AmenConnectSpacesAegisGateRequest(surface: surface, capabilityRefs: capabilityRefs, inputRef: inputRef, userId: userId, spaceId: spaceId, videoId: videoId)
    }

    static func validateCapabilityRefs(_ refs: [String]) throws {
        let invalid = refs.filter { !capabilityRefSet.contains($0) }
        guard invalid.isEmpty else { throw AmenConnectSpacesPhase0BindingError.invalidField("capabilityRefs") }
    }

    static func gateDecision(from data: [String: Any]) throws -> AmenConnectSpacesAegisGateDecision {
        let actionRaw = data["action"] as? String ?? AmenConnectSpacesAegisAction.allow.rawValue
        guard let action = AmenConnectSpacesAegisAction(rawValue: actionRaw) else {
            throw AmenConnectSpacesPhase0BindingError.invalidField("action")
        }
        let flags = try (data["flags"] as? [[String: Any]] ?? []).map(aegisFlag)
        return AmenConnectSpacesAegisGateDecision(
            action: action,
            flags: flags,
            humanResourceRefs: data["humanResourceRefs"] as? [String] ?? [],
            canContinue: data["canContinue"] as? Bool ?? action != .block
        )
    }

    static func ministryMemoryResult(from data: [String: Any]) throws -> AmenConnectSpacesMinistryMemoryResult {
        AmenConnectSpacesMinistryMemoryResult(
            id: try string(data, "id"),
            videoId: try string(data, "videoId"),
            timestampSeconds: try timeInterval(data, "timestampSeconds"),
            transcriptExcerpt: try string(data, "transcriptExcerpt"),
            owner: data["owner"] as? String,
            actionItemId: data["actionItemId"] as? String,
            confidence: try double(data, "confidence")
        )
    }

    private static func aegisFlag(_ data: [String: Any]) throws -> AmenConnectSpacesAegisFlag {
        guard let surfaceRaw = data["surface"] as? String,
              let surface = AmenConnectSpacesSurface(rawValue: surfaceRaw),
              let actionRaw = data["action"] as? String,
              let action = AmenConnectSpacesAegisAction(rawValue: actionRaw) else {
            throw AmenConnectSpacesPhase0BindingError.invalidField("flags")
        }
        let capabilityRef = try string(data, "capabilityRef")
        try validateCapabilityRefs([capabilityRef])
        return AmenConnectSpacesAegisFlag(
            id: data["id"] as? String ?? UUID().uuidString,
            capabilityRef: capabilityRef,
            surface: surface,
            severity: data["severity"] as? String ?? "stub",
            action: action,
            subjectRef: data["subjectRef"] as? String ?? "",
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? data["createdAt"] as? Date ?? Date()
        )
    }

    private static func string(_ data: [String: Any], _ key: String) throws -> String {
        guard let value = data[key] as? String else { throw AmenConnectSpacesPhase0BindingError.missingField(key) }
        return value
    }

    private static func double(_ data: [String: Any], _ key: String) throws -> Double {
        if let value = data[key] as? Double { return value }
        if let value = data[key] as? Int { return Double(value) }
        throw AmenConnectSpacesPhase0BindingError.invalidField(key)
    }

    private static func timeInterval(_ data: [String: Any], _ key: String) throws -> TimeInterval {
        try double(data, key)
    }
}

private extension AmenConnectSpacesFirestoreBinding {
    static func bindMessageConvictionCheckPayload(_ data: [String: Any]) throws -> AmenConnectSpacesConvictionCheck {
        AmenConnectSpacesConvictionCheck(
            enabled: data["enabled"] as? Bool ?? true,
            suggestedPause: data["suggestedPause"] as? Bool ?? false,
            warningKinds: (data["warningKinds"] as? [String] ?? []).compactMap(AmenConnectSpacesBeforeShareWarning.init(rawValue:)),
            checkedAt: (data["checkedAt"] as? Timestamp)?.dateValue() ?? data["checkedAt"] as? Date
        )
    }
}
