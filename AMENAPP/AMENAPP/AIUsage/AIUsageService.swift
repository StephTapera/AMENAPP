import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

@MainActor
final class AIUsageService: ObservableObject {
    static let shared = AIUsageService()

    private let db = Firestore.firestore()

    private init() {}

    // Record AI usage server-side (server determines primaryLabel and disclosureRequired)
    func recordUsage(
        targetType: String,
        targetId: String,
        aiUseTypes: [AIUseType],
        userAcceptedSuggestion: Bool,
        aiGeneratedPercentage: Double? = nil,
        toneCheckSummary: ToneCheckSummary? = nil
    ) async {
        guard Auth.auth().currentUser != nil else { return }

        do {
            let callable = Functions.functions().httpsCallable("recordPostAIUsage")
            var params: [String: Any] = [
                "targetType": targetType,
                "targetId": targetId,
                "aiUseTypes": aiUseTypes.map { $0.rawValue },
                "userAcceptedSuggestion": userAcceptedSuggestion
            ]
            if let pct = aiGeneratedPercentage { params["aiGeneratedPercentageEstimate"] = pct }
            if let summary = toneCheckSummary {
                params["toneCheckSummary"] = [
                    "kindnessScore": summary.kindnessScore,
                    "clarityScore": summary.clarityScore,
                    "humilityScore": summary.humilityScore,
                    "peaceScore": summary.peaceScore
                ]
            }
            _ = try await callable.call(params)
        } catch { dlog("⚠️ AIUsageService.recordUsage: \(error)") }
    }

    // Fetch label detail for display
    func fetchLabelDetail(targetType: String, targetId: String) async -> PostAIUsage? {
        do {
            let callable = Functions.functions().httpsCallable("getAILabelDetail")
            let result = try await callable.call([
                "targetType": targetType,
                "targetId": targetId
            ])
            if let data = result.data as? [String: Any],
               let jsonData = try? JSONSerialization.data(withJSONObject: data) {
                return try? JSONDecoder().decode(PostAIUsage.self, from: jsonData)
            }
        } catch { dlog("⚠️ AIUsageService.fetchLabelDetail: \(error)") }
        return nil
    }

    // Log analytics event (no raw text ever stored)
    func logEvent(
        targetType: String,
        targetId: String,
        aiUseTypes: [AIUseType],
        primaryLabel: PostAILabel?,
        eventType: String
    ) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let event = AIUsageEvent(
            id: nil,
            userId: uid,
            targetType: targetType,
            targetId: targetId,
            aiUseTypes: aiUseTypes.map { $0.rawValue },
            primaryLabel: primaryLabel?.rawValue,
            eventType: eventType
        )

        do {
            _ = try db.collection("users").document(uid)
                .collection("aiUsageEvents").addDocument(from: event)
        } catch { dlog("⚠️ AIUsageService.logEvent: \(error)") }
    }

    // ToneChecker: evaluate tone through backend AI only (never exposes API keys)
    func evaluateTone(text: String, context: String, isRestModeActive: Bool) async -> ToneCheckResult? {
        do {
            let callable = Functions.functions().httpsCallable("evaluateTone")
            let result = try await callable.call([
                "text": text,
                "context": context,
                "isRestModeActive": isRestModeActive
            ])
            if let data = result.data as? [String: Any],
               let jsonData = try? JSONSerialization.data(withJSONObject: data),
               let decoded = try? JSONDecoder().decode(ToneCheckResult.self, from: jsonData) {
                return decoded
            }
        } catch { dlog("⚠️ AIUsageService.evaluateTone: \(error)") }
        return nil
    }
}

// MARK: - Tone Check Result

struct ToneCheckResult: Codable {
    var kindnessScore: Double
    var clarityScore: Double
    var humilityScore: Double
    var peaceScore: Double
    var truthfulnessScore: Double
    var scriptureIntegrityScore: Double?
    var shameLanguageRisk: Double
    var manipulationRisk: Double
    var pastoralSensitivityScore: Double
    var concerns: [String]
    var suggestedRewrite: String?
    var suggestedMode: String?
    var labelIfPublished: String?
    var saveForMondayRecommended: Bool
}
