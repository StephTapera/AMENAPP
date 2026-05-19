import Foundation
import FirebaseAuth
import FirebaseFunctions

@MainActor
final class BereanContextActionEngine: ObservableObject {
    static let shared = BereanContextActionEngine()

    @Published private(set) var isLoading = false
    @Published private(set) var lastResult: BereanContextActionResult?
    @Published private(set) var lastErrorMessage: String?

    private let functions = Functions.functions()

    func perform(_ action: BereanContextAction, payload: BereanContextPayload) async -> BereanContextActionResult? {
        guard AMENFeatureFlags.shared.bereanLiquidGlassContextActionsEnabled else {
            AMENAnalyticsService.shared.track(.bereanFeatureFlagBlocked(feature: "berean_liquid_glass_context_actions"))
            lastErrorMessage = "Berean context actions are not available right now."
            return nil
        }

        guard Auth.auth().currentUser != nil else {
            lastErrorMessage = "Sign in to use Berean context actions."
            return nil
        }

        isLoading = true
        lastResult = nil
        lastErrorMessage = nil
        AMENAnalyticsService.shared.track(.bereanStudyActionStarted(action: action.rawValue))

        do {
            let result = try await functions.httpsCallable("routeBereanContextualAction").call([
                "action": action.rawValue,
                "payload": payload.dictionaryValue
            ])
            guard let data = result.data as? [String: Any] else {
                throw BereanContextActionError.invalidResponse
            }
            let response = BereanContextActionResult(
                id: data["id"] as? String ?? UUID().uuidString,
                action: action,
                title: data["title"] as? String ?? action.title,
                answer: data["answer"] as? String ?? "",
                scriptureReferences: data["scriptureReferences"] as? [String] ?? [],
                suggestedActions: data["suggestedActions"] as? [String] ?? [],
                safetyNotice: data["safetyNotice"] as? String,
                threadId: data["threadId"] as? String
            )
            lastResult = response
            AMENAnalyticsService.shared.track(.bereanStudyActionCompleted(action: action.rawValue))
            isLoading = false
            return response
        } catch {
            lastErrorMessage = "Berean could not complete this action. Please try again."
            AMENAnalyticsService.shared.track(.bereanProviderFailure(reason: "context_action_failed"))
            isLoading = false
            return nil
        }
    }

    func clearResult() {
        lastResult = nil
        lastErrorMessage = nil
    }
}

enum BereanContextActionError: Error {
    case invalidResponse
}

private extension BereanContextPayload {
    var dictionaryValue: [String: Any] {
        [
            "id": id,
            "selectedText": selectedText,
            "surroundingText": surroundingText ?? "",
            "sourceSurface": sourceSurface,
            "sourceId": sourceId ?? "",
            "contentType": contentType.rawValue,
            "scriptureReference": scriptureReference ?? "",
            "languageCode": languageCode ?? "",
            "metadata": metadata
        ]
    }
}
