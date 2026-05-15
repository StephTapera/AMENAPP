import Foundation
import FirebaseFunctions

// MARK: - AmenSemanticIntelligenceService
//
// Client-side gateway for the five Semantic Intelligence Cloud Functions.
// All AI outputs are server-generated — the client never writes trusted AI
// content directly to Firestore.

@MainActor
final class AmenSemanticIntelligenceService: ObservableObject {
    static let shared = AmenSemanticIntelligenceService()

    private let functions = Functions.functions()

    private init() {}

    // MARK: - defineSemanticTerm

    struct DefineTermRequest: Encodable {
        let term: String
        let sourceText: String
        let sourceType: String
        let sourceId: String
        let userLocale: String
        let requestedDepth: String   // "compact" | "expanded" | "biblical"
        let screenContext: String
    }

    /// Calls the `defineSemanticTerm` Cloud Function.
    /// Returns a cached definition if available.
    func defineSemanticTerm(
        term: String,
        sourceText: String,
        sourceType: String = "post",
        sourceId: String = "",
        depth: String = "compact",
        screenContext: String = "feed"
    ) async throws -> AmenSemanticDefinition {
        let req = DefineTermRequest(
            term: term,
            sourceText: String(sourceText.prefix(500)),
            sourceType: sourceType,
            sourceId: sourceId,
            userLocale: Locale.current.identifier,
            requestedDepth: depth,
            screenContext: screenContext
        )
        let data = try encodeToDict(req)
        let result = try await functions
            .httpsCallable("defineSemanticTerm")
            .call(data)

        guard let dict = result.data as? [String: Any] else {
            throw ServiceError.invalidResponse
        }
        return try parseDefinition(dict)
    }

    // MARK: - detectSmartActions

    struct DetectActionsRequest: Encodable {
        let screen: String
        let sourceType: String
        let sourceId: String
        let visibleText: String
        let selectedText: String
        let featureFlags: [String: Bool]
    }

    struct DetectedActionsResponse {
        let rankedActions: [SmartActionDescriptor]
        let suppressedActions: [String]
        let reasonCodes: [String]
    }

    struct SmartActionDescriptor: Identifiable {
        let id: String
        let icon: String
        let title: String
        let subtitle: String?
        let priorityRaw: Int
        let analyticsEvent: String
    }

    func detectSmartActions(
        screen: String,
        sourceType: String,
        sourceId: String,
        visibleText: String,
        selectedText: String = "",
        featureFlags: [String: Bool] = [:]
    ) async throws -> DetectedActionsResponse {
        let req = DetectActionsRequest(
            screen: screen,
            sourceType: sourceType,
            sourceId: sourceId,
            visibleText: String(visibleText.prefix(800)),
            selectedText: String(selectedText.prefix(300)),
            featureFlags: featureFlags
        )
        let data = try encodeToDict(req)
        let result = try await functions
            .httpsCallable("detectSmartActions")
            .call(data)

        guard let dict = result.data as? [String: Any] else {
            throw ServiceError.invalidResponse
        }
        return try parseDetectedActions(dict)
    }

    // MARK: - createKnowledgeThread

    struct CreateKnowledgeThreadRequest: Encodable {
        let term: String
        let sourceType: String
        let sourceId: String
        let definitionId: String
        let relatedRefs: [String]
        let userNote: String?
    }

    func createKnowledgeThread(
        term: String,
        sourceType: String,
        sourceId: String,
        definitionId: String,
        relatedRefs: [String],
        userNote: String? = nil
    ) async throws -> String {
        let req = CreateKnowledgeThreadRequest(
            term: term,
            sourceType: sourceType,
            sourceId: sourceId,
            definitionId: definitionId,
            relatedRefs: relatedRefs,
            userNote: userNote
        )
        let data = try encodeToDict(req)
        let result = try await functions
            .httpsCallable("createKnowledgeThread")
            .call(data)

        guard let dict = result.data as? [String: Any],
              let threadId = dict["threadId"] as? String else {
            throw ServiceError.invalidResponse
        }
        return threadId
    }

    // MARK: - saveSemanticInsight

    struct SaveInsightRequest: Encodable {
        let definitionId: String
        let term: String
        let sourceType: String
        let sourceId: String
        let userNote: String?
    }

    func saveSemanticInsight(
        definitionId: String,
        term: String,
        sourceType: String,
        sourceId: String,
        userNote: String? = nil
    ) async throws -> String {
        let req = SaveInsightRequest(
            definitionId: definitionId,
            term: term,
            sourceType: sourceType,
            sourceId: sourceId,
            userNote: userNote
        )
        let data = try encodeToDict(req)
        let result = try await functions
            .httpsCallable("saveSemanticInsight")
            .call(data)

        guard let dict = result.data as? [String: Any],
              let savedId = dict["savedInsightId"] as? String else {
            throw ServiceError.invalidResponse
        }
        return savedId
    }

    // MARK: - logPresenceSignal

    struct LogPresenceRequest: Encodable {
        let screen: String
        let signalType: String
        let sourceId: String?
        let metadata: [String: String]
    }

    func logPresenceSignal(
        screen: String,
        signalType: AmenPulseSignalType,
        sourceId: String? = nil,
        metadata: [String: String] = [:]
    ) async {
        // Fire-and-forget — failures are silently dropped to avoid interrupting UX.
        do {
            let req = LogPresenceRequest(
                screen: screen,
                signalType: signalType.rawValue,
                sourceId: sourceId,
                metadata: metadata
            )
            let data = try encodeToDict(req)
            _ = try await functions
                .httpsCallable("logPresenceSignal")
                .call(data)
        } catch {
            // Intentional no-op: presence signals are best-effort, non-critical
        }
    }

    // MARK: - Parsing Helpers

    private func parseDefinition(_ dict: [String: Any]) throws -> AmenSemanticDefinition {
        guard
            let id = dict["id"] as? String,
            let term = dict["term"] as? String,
            let compact = dict["compactDefinition"] as? String
        else { throw ServiceError.invalidResponse }

        let refs = dict["relatedScriptureRefs"] as? [String] ?? []
        let confidence = dict["confidence"] as? Double ?? 0.5
        let generatedAt: Date
        if let ts = dict["generatedAt"] as? Double {
            generatedAt = Date(timeIntervalSince1970: ts)
        } else {
            generatedAt = Date()
        }

        return AmenSemanticDefinition(
            id: id,
            term: term,
            compactDefinition: compact,
            expandedDefinition: dict["expandedDefinition"] as? String,
            biblicalContext: dict["biblicalContext"] as? String,
            relatedScriptureRefs: refs,
            confidence: confidence,
            safetyNotes: dict["safetyNotes"] as? String,
            generatedAt: generatedAt,
            modelUsed: dict["modelUsed"] as? String ?? "unknown",
            cacheStatus: dict["cacheStatus"] as? String ?? "miss"
        )
    }

    private func parseDetectedActions(_ dict: [String: Any]) throws -> DetectedActionsResponse {
        let rawActions = dict["rankedActions"] as? [[String: Any]] ?? []
        let actions = rawActions.compactMap { a -> SmartActionDescriptor? in
            guard let id = a["id"] as? String, let title = a["title"] as? String else { return nil }
            return SmartActionDescriptor(
                id: id,
                icon: a["icon"] as? String ?? "sparkles",
                title: title,
                subtitle: a["subtitle"] as? String,
                priorityRaw: a["priorityRaw"] as? Int ?? 7,
                analyticsEvent: a["analyticsEvent"] as? String ?? "smart_action_tapped"
            )
        }
        return DetectedActionsResponse(
            rankedActions: Array(actions.prefix(3)),
            suppressedActions: dict["suppressedActions"] as? [String] ?? [],
            reasonCodes: dict["reasonCodes"] as? [String] ?? []
        )
    }

    private func encodeToDict<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ServiceError.encodingFailed
        }
        return dict
    }

    // MARK: - Errors

    enum ServiceError: LocalizedError {
        case invalidResponse
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "Unexpected response from intelligence service."
            case .encodingFailed:  return "Failed to encode request."
            }
        }
    }
}
