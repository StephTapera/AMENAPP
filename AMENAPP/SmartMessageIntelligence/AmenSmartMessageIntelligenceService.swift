import Foundation
import FirebaseAnalytics
import FirebaseFunctions

@MainActor
final class AmenSmartMessageIntelligenceService: ObservableObject {
    static let shared = AmenSmartMessageIntelligenceService()

    @Published private(set) var isLoading = false
    @Published private(set) var lastError: SmartMessageIntelligenceError?

    private let functions = Functions.functions()
    private let flags = AMENFeatureFlags.shared
    private var inFlightCalls: [String: Task<[String: Any], Error>] = [:]

    private init() {}

    func analyzeMessage(spaceId: String, threadId: String, messageId: String, text: String) async throws -> SmartMessageAnalysisResponse {
        try ensure(flags.smartMessageIntelligenceEnabled, "Smart Message Intelligence")
        return try await callSmartResponse("analyzeSmartMessage", payload: [
            "spaceId": spaceId,
            "threadId": threadId,
            "messageId": messageId,
            "text": text
        ], analyticsEvent: "smart_message_analyzed")
    }

    func detectScriptures(in text: String) async throws -> [SmartDetectedEntity] {
        try ensure(flags.scriptureDetectionEnabled, "Scripture detection")
        return try await callSmartResponse("detectScriptureReferences", payload: ["text": text], analyticsEvent: "smart_entity_detected").detectedEntities
    }

    func detectDateEvents(in text: String) async throws -> [SmartDetectedEntity] {
        try ensure(flags.smartEventDetectionEnabled, "Smart event detection")
        return try await callSmartResponse("detectSmartDateEvents", payload: ["text": text], analyticsEvent: "smart_entity_detected").detectedEntities
    }

    func detectPrayerRequest(in text: String) async throws -> [SmartDetectedEntity] {
        try ensure(flags.prayerIntelligenceEnabled, "Prayer intelligence")
        return try await callSmartResponse("detectPrayerRequest", payload: ["text": text], analyticsEvent: "smart_entity_detected").detectedEntities
    }

    func summarizeDiscussion(spaceId: String, threadId: String, messageIds: [String]) async throws -> SmartDiscussionInsight {
        try ensure(flags.discussionSummariesEnabled, "Discussion summaries")
        let dict = try await callDictionary("summarizeDiscussion", payload: ["spaceId": spaceId, "threadId": threadId, "messageIds": messageIds])
        Analytics.logEvent("discussion_summary_created", parameters: ["space_id": spaceId, "thread_id": threadId])
        return parseInsight(dict)
    }

    func getBereanActions(selectedText: String, source: SmartMessageSource) async throws -> [SmartMessageAction] {
        try ensure(flags.contextualBereanActionsEnabled, "Contextual Berean actions")
        var payload: [String: Any] = ["selectedText": selectedText, "sourceType": source.sourceType, "sourceId": source.sourceId]
        if let spaceId = source.spaceId { payload["spaceId"] = spaceId }
        if let threadId = source.threadId { payload["threadId"] = threadId }
        let dict = try await callDictionary("getContextualBereanActions", payload: payload)
        return parseActions(dict["actions"] as? [[String: Any]] ?? [])
    }

    func extractTopics(spaceId: String, threadId: String, messageId: String, text: String) async throws -> [SmartDetectedEntity] {
        try ensure(flags.topicExtractionEnabled, "Topic extraction")
        return try await callSmartResponse("extractDiscussionTopics", payload: ["spaceId": spaceId, "threadId": threadId, "messageId": messageId, "text": text], analyticsEvent: "smart_entity_detected").detectedEntities
    }

    func semanticSearch(spaceId: String, query: String, filters: [String: String] = [:]) async throws -> [SmartSearchResult] {
        try await semanticSearchResponse(spaceId: spaceId, query: query, filters: filters).results
    }

    func semanticSearchResponse(spaceId: String, query: String, filters: [String: String] = [:]) async throws -> SmartSearchResponse {
        try ensure(flags.semanticSearchEnabled, "Amen Space search")
        let dict = try await callDictionary("semanticSearchAmenSpace", payload: ["spaceId": spaceId, "query": query, "filters": filters])
        let rankingMode = SmartSearchRankingMode(rawValue: dict["rankingMode"] as? String ?? "") ?? .unknown
        let results = (dict["results"] as? [[String: Any]] ?? []).map(parseSearchResult)
        Analytics.logEvent("semantic_search_performed", parameters: ["space_id": spaceId, "ranking_mode": rankingMode.rawValue, "result_count": results.count])
        return SmartSearchResponse(rankingMode: rankingMode, results: results)
    }

    func startStudyMode(spaceId: String, threadId: String, seedMessageIds: [String], title: String? = nil) async throws -> SmartStudySession {
        try ensure(flags.studyModeEnabled, "Study Mode")
        var payload: [String: Any] = ["spaceId": spaceId, "threadId": threadId, "seedMessageIds": seedMessageIds]
        if let title { payload["title"] = title }
        let dict = try await callDictionary("startSmartStudyMode", payload: payload)
        Analytics.logEvent("study_mode_started", parameters: ["space_id": spaceId, "thread_id": threadId])
        guard let sessionDict = dict["session"] as? [String: Any] else { throw SmartMessageIntelligenceError.invalidResponse }
        return parseStudySession(sessionDict)
    }

    func transcribeVoiceMessage(spaceId: String, threadId: String, messageId: String, audioStoragePath: String, transcript: String? = nil) async throws -> SmartMessageAnalysisResponse {
        try ensure(flags.voiceIntelligenceEnabled, "Voice intelligence")
        var resolvedTranscript = transcript?.trimmingCharacters(in: .whitespacesAndNewlines)
        if resolvedTranscript?.isEmpty ?? true {
            let whisperResult = try await functions.httpsCallable("whisperProxy").call([
                "audioURL": audioStoragePath,
                "prompt": "Transcribe this Amen voice message accurately."
            ])
            guard let dict = whisperResult.data as? [String: Any],
                  let text = dict["text"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SmartMessageIntelligenceError.invalidResponse
            }
            resolvedTranscript = text
        }
        let payload: [String: Any] = [
            "spaceId": spaceId,
            "threadId": threadId,
            "messageId": messageId,
            "audioStoragePath": audioStoragePath,
            "transcript": resolvedTranscript ?? ""
        ]
        return try await callSmartResponse("transcribeVoiceMessage", payload: payload, analyticsEvent: "voice_transcription_completed")
    }

    func buildKnowledgeGraph(scope: SmartKnowledgeScope, source: SmartMessageSource, text: String = "") async throws -> SmartKnowledgeNode {
        try ensure(flags.knowledgeGraphMemoryEnabled, "Knowledge graph memory")
        var payload: [String: Any] = ["scope": scope.rawValue, "sourceType": source.sourceType, "sourceId": source.sourceId, "text": text]
        if let spaceId = source.spaceId { payload["spaceId"] = spaceId }
        let dict = try await callDictionary("buildKnowledgeGraphMemory", payload: payload)
        Analytics.logEvent("knowledge_graph_node_created", parameters: ["scope": scope.rawValue])
        guard let nodeDict = dict["node"] as? [String: Any] else { throw SmartMessageIntelligenceError.invalidResponse }
        return parseKnowledgeNode(nodeDict)
    }

    func trackActionTapped(_ action: SmartMessageAction) {
        Analytics.logEvent("smart_action_tapped", parameters: ["action_type": action.actionType.rawValue])
    }

    func trackActionConfirmed(_ action: SmartMessageAction) {
        Analytics.logEvent("smart_action_confirmed", parameters: ["action_type": action.actionType.rawValue])
    }

    private func ensure(_ enabled: Bool, _ feature: String) throws {
        guard enabled else { throw SmartMessageIntelligenceError.featureDisabled(feature) }
    }

    private func callSmartResponse(_ name: String, payload: [String: Any], analyticsEvent: String) async throws -> SmartMessageAnalysisResponse {
        let dict = try await callDictionary(name, payload: payload)
        let response = SmartMessageAnalysisResponse(
            detectedEntities: parseEntities(dict["detectedEntities"] as? [[String: Any]] ?? []),
            suggestedActions: parseActions(dict["suggestedActions"] as? [[String: Any]] ?? [])
        )
        Analytics.logEvent(analyticsEvent, parameters: ["entity_count": response.detectedEntities.count, "action_count": response.suggestedActions.count])
        return response
    }

    private func callDictionary(_ name: String, payload: [String: Any]) async throws -> [String: Any] {
        let key = callKey(name: name, payload: payload)
        if let existing = inFlightCalls[key] {
            return try await existing.value
        }

        isLoading = true
        lastError = nil
        let startedAt = Date()
        let task = Task { [functions] in
            let result = try await functions.httpsCallable(name).call(payload)
            guard let dict = result.data as? [String: Any] else { throw SmartMessageIntelligenceError.invalidResponse }
            return dict
        }
        inFlightCalls[key] = task
        defer {
            inFlightCalls[key] = nil
            isLoading = !inFlightCalls.isEmpty
        }
        do {
            let dict = try await task.value
            trackCallableCompleted(name: name, startedAt: startedAt, succeeded: true, errorCategory: nil)
            return dict
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as SmartMessageIntelligenceError {
            lastError = error
            trackCallableCompleted(name: name, startedAt: startedAt, succeeded: false, errorCategory: "smart_message")
            throw error
        } catch {
            let mapped = SmartMessageIntelligenceError.providerUnavailable(error.localizedDescription)
            lastError = mapped
            trackCallableCompleted(name: name, startedAt: startedAt, succeeded: false, errorCategory: String(describing: type(of: error)))
            throw mapped
        }
    }

    private func trackCallableCompleted(name: String, startedAt: Date, succeeded: Bool, errorCategory: String?) {
        var parameters: [String: Any] = [
            "callable": name,
            "succeeded": succeeded,
            "latency_ms": Int(Date().timeIntervalSince(startedAt) * 1000)
        ]
        if let errorCategory {
            parameters["error_category"] = errorCategory
        }
        Analytics.logEvent("smart_message_callable_completed", parameters: parameters)
    }

    private func callKey(name: String, payload: [String: Any]) -> String {
        let payloadFingerprint = payload.keys.sorted().map { key in
            "\(key)=\(String(describing: payload[key] ?? "").hashValue)"
        }.joined(separator: "&")
        return "\(name)|\(payloadFingerprint)"
    }
}

private extension AmenSmartMessageIntelligenceService {
    func parseEntities(_ items: [[String: Any]]) -> [SmartDetectedEntity] {
        items.compactMap { item in
            guard let id = item["id"] as? String,
                  let typeRaw = item["type"] as? String,
                  let type = SmartDetectedEntityType(rawValue: typeRaw) else { return nil }
            let rangeDict = item["range"] as? [String: Any] ?? [:]
            return SmartDetectedEntity(
                id: id,
                type: type,
                sourceText: item["sourceText"] as? String ?? "",
                normalizedValue: item["normalizedValue"] as? String ?? "",
                confidence: item["confidence"] as? Double ?? 0,
                range: SmartTextRange(start: rangeDict["start"] as? Int ?? 0, length: rangeDict["length"] as? Int ?? 0),
                createdAt: date(from: item["createdAt"])
            )
        }
    }

    func parseActions(_ items: [[String: Any]]) -> [SmartMessageAction] {
        items.compactMap { item in
            guard let id = item["id"] as? String,
                  let actionRaw = item["actionType"] as? String,
                  let actionType = SmartMessageActionType(rawValue: actionRaw) else { return nil }
            let payloadAny = item["payload"] as? [String: Any] ?? [:]
            let payload = payloadAny.reduce(into: [String: String]()) { $0[$1.key] = String(describing: $1.value) }
            return SmartMessageAction(
                id: id,
                title: item["title"] as? String ?? actionType.rawValue,
                subtitle: item["subtitle"] as? String ?? "",
                iconSystemName: item["iconSystemName"] as? String ?? "sparkles",
                actionType: actionType,
                payload: payload,
                requiresConfirmation: item["requiresConfirmation"] as? Bool ?? true,
                privacyLevel: SmartMessagePrivacyLevel(rawValue: item["privacyLevel"] as? String ?? "private") ?? .private
            )
        }
    }

    func parseInsight(_ item: [String: Any]) -> SmartDiscussionInsight {
        SmartDiscussionInsight(
            summary: item["summary"] as? String ?? "",
            keyTakeaways: item["keyTakeaways"] as? [String] ?? [],
            scriptures: item["scriptures"] as? [String] ?? [],
            prayerRequests: item["prayerRequests"] as? [String] ?? [],
            topics: item["topics"] as? [String] ?? [],
            actionItems: item["actionItems"] as? [String] ?? [],
            unresolvedQuestions: item["unresolvedQuestions"] as? [String] ?? [],
            suggestedNextActions: parseActions(item["suggestedNextActions"] as? [[String: Any]] ?? [])
        )
    }

    func parseStudySession(_ item: [String: Any]) -> SmartStudySession {
        SmartStudySession(
            id: item["id"] as? String ?? UUID().uuidString,
            spaceId: item["spaceId"] as? String ?? "",
            threadId: item["threadId"] as? String ?? "",
            title: item["title"] as? String ?? "Smart Study",
            scriptures: item["scriptures"] as? [String] ?? [],
            topics: item["topics"] as? [String] ?? [],
            notes: item["notes"] as? [String] ?? [],
            participants: item["participants"] as? [String] ?? [],
            createdBy: item["createdBy"] as? String ?? "",
            createdAt: date(from: item["createdAt"]),
            updatedAt: date(from: item["updatedAt"])
        )
    }

    func parseKnowledgeNode(_ item: [String: Any]) -> SmartKnowledgeNode {
        SmartKnowledgeNode(
            id: item["id"] as? String ?? UUID().uuidString,
            ownerScope: item["ownerScope"] as? String ?? "user",
            nodeType: item["nodeType"] as? String ?? "topic",
            title: item["title"] as? String ?? "Memory",
            summary: item["summary"] as? String ?? "",
            scriptureRefs: item["scriptureRefs"] as? [String] ?? [],
            topics: item["topics"] as? [String] ?? [],
            linkedMessageIds: item["linkedMessageIds"] as? [String] ?? [],
            linkedThreadIds: item["linkedThreadIds"] as? [String] ?? [],
            linkedSpaceIds: item["linkedSpaceIds"] as? [String] ?? [],
            createdAt: date(from: item["createdAt"]),
            updatedAt: date(from: item["updatedAt"])
        )
    }

    func parseSearchResult(_ item: [String: Any]) -> SmartSearchResult {
        SmartSearchResult(
            id: item["id"] as? String ?? UUID().uuidString,
            sourceType: item["sourceType"] as? String ?? "message",
            title: item["title"] as? String ?? "Result",
            snippet: item["snippet"] as? String ?? "",
            score: item["score"] as? Double ?? 0,
            path: item["path"] as? String ?? ""
        )
    }

    func date(from value: Any?) -> Date {
        if let milliseconds = value as? Double { return Date(timeIntervalSince1970: milliseconds / 1000) }
        if let seconds = value as? TimeInterval { return Date(timeIntervalSince1970: seconds / 1000) }
        return Date()
    }
}

private extension SmartMessageSource {
    var sourceType: String {
        switch self {
        case .message: return "message"
        case .thread: return "thread"
        case .space: return "space"
        case .local: return "local"
        }
    }

    var sourceId: String {
        switch self {
        case .message(_, _, let messageId): return messageId
        case .thread(_, let threadId): return threadId
        case .space(let spaceId): return spaceId
        case .local(let sourceId): return sourceId
        }
    }

    var spaceId: String? {
        switch self {
        case .message(let spaceId, _, _), .thread(let spaceId, _), .space(let spaceId): return spaceId
        case .local: return nil
        }
    }

    var threadId: String? {
        switch self {
        case .message(_, let threadId, _), .thread(_, let threadId): return threadId
        case .space, .local: return nil
        }
    }
}
