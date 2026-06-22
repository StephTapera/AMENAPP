import Foundation
import FirebaseAuth
import FirebaseFunctions
import FirebaseFirestore

@MainActor
final class BiblicalAlignmentService {
    static let shared = BiblicalAlignmentService()

    private let functions = Functions.functions()
    private let db = Firestore.firestore()

    private init() {}

    func checkBiblicalAlignment(
        text: String,
        targetType: String,
        targetId: String? = nil,
        sourceSurface: String,
        requestedLens: AlignmentLens? = nil,
        hasMedia: Bool = false
    ) async throws -> BiblicalAlignmentCheckResult {
        guard Auth.auth().currentUser != nil else {
            throw NSError(domain: "BiblicalAlignmentService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }

        let payload: [String: Any] = [
            "text": text,
            "targetType": targetType,
            "targetId": targetId as Any,
            "sourceSurface": sourceSurface,
            "requestedLens": requestedLens?.rawValue as Any,
            "hasMedia": hasMedia
        ]

        let result = try await functions.httpsCallable("checkBiblicalAlignment").call(payload)
        return try decode(BiblicalAlignmentCheckResult.self, from: result.data)
    }

    func suggestBiblicalRewrite(
        originalText: String,
        lens: AlignmentLens,
        targetType: String
    ) async throws -> (rewrittenText: String, explanation: String, scriptureSuggestions: [ScriptureSuggestion]) {
        let result = try await functions.httpsCallable("suggestBiblicalRewrite").call([
            "originalText": originalText,
            "lens": lens.rawValue,
            "targetType": targetType
        ])
        let data = result.data as? [String: Any] ?? [:]
        return (
            data["rewrittenText"] as? String ?? originalText,
            data["explanation"] as? String ?? "",
            decodeArray(ScriptureSuggestion.self, from: data["scriptureSuggestions"])
        )
    }

    func saveAICorrection(
        originalCheckId: String? = nil,
        targetType: String,
        targetId: String? = nil,
        originalText: String? = nil,
        correctionText: String,
        selectedLens: AlignmentLens,
        correctionIntent: String,
        savedToProfile: Bool
    ) async throws -> Bool {
        let result = try await functions.httpsCallable("saveAICorrection").call([
            "originalCheckId": originalCheckId as Any,
            "targetType": targetType,
            "targetId": targetId as Any,
            "originalText": originalText as Any,
            "correctionText": correctionText,
            "selectedLens": selectedLens.rawValue,
            "correctionIntent": correctionIntent,
            "savedToProfile": savedToProfile
        ])
        let data = result.data as? [String: Any] ?? [:]
        return data["profileUpdated"] as? Bool ?? false
    }

    func getDiscernmentPrompt(text: String, surface: String) async throws -> DiscernmentPromptResult {
        let result = try await functions.httpsCallable("getDiscernmentPrompt").call([
            "text": text,
            "surface": surface
        ])
        return try decode(DiscernmentPromptResult.self, from: result.data)
    }

    func attachSharedKnowledgeIntegrity(
        targetType: String,
        targetId: String,
        checkId: String
    ) async throws {
        _ = try await functions.httpsCallable("attachSharedKnowledgeIntegrity").call([
            "targetType": targetType,
            "targetId": targetId,
            "checkId": checkId
        ])
    }

    func voteKnowledgeIntegrity(targetType: String, targetId: String, vote: String) async throws {
        _ = try await functions.httpsCallable("voteKnowledgeIntegrity").call([
            "targetType": targetType,
            "targetId": targetId,
            "vote": vote
        ])
    }

    func getWeeklyAlignmentSummary(weekStart: String? = nil) async throws -> WeeklyAlignmentSummary? {
        let result = try await functions.httpsCallable("getWeeklyAlignmentSummary").call([
            "weekStart": weekStart as Any
        ])
        let data = result.data as? [String: Any] ?? [:]
        guard let summary = data["summary"] else { return nil }
        return try decode(WeeklyAlignmentSummary.self, from: summary)
    }

    func updateAlignmentProfile(
        defaultLens: AlignmentLens? = nil,
        discernmentMode: DiscernmentMode? = nil,
        scripturePreference: String? = nil,
        correctionMemoryEnabled: Bool? = nil,
        weeklySummaryEnabled: Bool? = nil,
        simpleModeEnabled: Bool? = nil,
        explicitContentProtectionEnabled: Bool? = nil,
        exploitationProtectionEnabled: Bool? = nil,
        preferredTone: String? = nil
    ) async throws -> AlignmentProfile {
        let result = try await functions.httpsCallable("updateAlignmentProfile").call([
            "defaultLens": defaultLens?.rawValue as Any,
            "discernmentMode": discernmentMode?.rawValue as Any,
            "scripturePreference": scripturePreference as Any,
            "correctionMemoryEnabled": correctionMemoryEnabled as Any,
            "weeklySummaryEnabled": weeklySummaryEnabled as Any,
            "simpleModeEnabled": simpleModeEnabled as Any,
            "explicitContentProtectionEnabled": explicitContentProtectionEnabled as Any,
            "exploitationProtectionEnabled": exploitationProtectionEnabled as Any,
            "preferredTone": preferredTone as Any
        ])
        let data = result.data as? [String: Any] ?? [:]
        return try decode(AlignmentProfile.self, from: data["profile"] as Any)
    }

    func fetchIntegrityRecord(targetType: String, targetId: String) async -> SharedKnowledgeIntegrityRecord? {
        let docId = "\(targetType)_\(targetId)"
        guard let snapshot = try? await db.collection("shared_knowledge_integrity").document(docId).getDocument(),
              let data = snapshot.data() else {
            return nil
        }
        return try? decode(SharedKnowledgeIntegrityRecord.self, from: data)
    }

    private func decode<T: Decodable>(_ type: T.Type, from raw: Any) throws -> T {
        let json = try JSONSerialization.data(withJSONObject: normalize(raw), options: [])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: json)
    }

    private func decodeArray<T: Decodable>(_ type: T.Type, from raw: Any?) -> [T] {
        guard let raw else { return [] }
        return (try? decode([T].self, from: raw)) ?? []
    }

    private func normalize(_ raw: Any) -> Any {
        if let timestamp = raw as? Timestamp {
            return ISO8601DateFormatter().string(from: timestamp.dateValue())
        }
        if let dict = raw as? [String: Any] {
            return dict.mapValues { normalize($0) }
        }
        if let array = raw as? [Any] {
            return array.map { normalize($0) }
        }
        return raw
    }
}
