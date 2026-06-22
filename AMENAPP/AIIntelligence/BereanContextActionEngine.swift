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
    // Constitutional gate — serial actor, shared across the app.
    private let constitutionGate = BereanConstitutionalReviewGate.shared

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

        // Constitutional pre-flight gate (must pass before any AI call).
        // Derives the appropriate mode from the action, then checks payload
        // integrity, crisis signals, medical guardrail, and high-impact action rules.
        let constitutionResult = await constitutionGate.review(action: action, payload: payload)
        guard constitutionResult.passed else {
            let reason = constitutionResult.blockedReasons.first ?? "Constitutional review did not pass."
            dlog("[Berean] Constitutional gate blocked '\(action.rawValue)': \(constitutionResult.blockedReasons.joined(separator: "; "))")
            lastErrorMessage = reason.contains("Crisis") || reason.contains("crisis")
                ? "It sounds like you may be going through something difficult. Please reach out for support."
                : "Berean could not process this request. Please try again."
            AMENAnalyticsService.shared.track(.bereanProviderFailure(reason: "constitutional_gate_blocked"))
            return nil
        }

        isLoading = true
        lastResult = nil
        lastErrorMessage = nil
        AMENAnalyticsService.shared.track(.bereanStudyActionStarted(action: action.rawValue))

        do {
            let result = try await functions.httpsCallable("routeBereanContextualAction").call([
                "action": action.rawValue,
                "payload": payload.dictionaryValue,
                "constitutionalMode": constitutionResult.requiredMode.rawValue
            ])
            guard let data = result.data as? [String: Any] else {
                throw BereanContextActionError.invalidResponse
            }
            let rawScriptureRefs = data["scriptureReferences"] as? [String] ?? []

            // SWEEP-1: Route scriptureReferences through verifyWithAPIPipeline before render.
            // claimedTexts is empty — the CF response provides refs only, not verse bodies.
            // The pipeline will still look them up for canonical text and detect mismatches.
            let verificationReport: ScriptureReferenceValidator.ScriptureVerificationReport
            if rawScriptureRefs.isEmpty {
                verificationReport = ScriptureReferenceValidator.ScriptureVerificationReport(
                    verifiedRefs: [],
                    mismatchRefs: [],
                    unresolvableRefs: [],
                    epistemicDeclaration: .empty
                )
            } else {
                verificationReport = await ScriptureReferenceValidator.verifyWithAPIPipeline(
                    references: rawScriptureRefs,
                    claimedTexts: [:],
                    translation: "KJV",
                    mode: constitutionResult.requiredMode
                )
            }

            // Apply mode policy: blockOnMismatch modes (.guard, .discern) strip mismatch refs;
            // annotateOnMismatch modes keep all refs but the EpistemicDeclaration records unknowns.
            let verifiedScriptureRefs: [String]
            let policy = BereanConstitutionalReviewGate.scriptureVerificationPolicy(
                for: constitutionResult.requiredMode
            )
            switch policy {
            case .blockOnMismatch:
                let mismatchRefSet = Set(verificationReport.mismatchRefs.map(\.ref))
                let unresolvableRefSet = Set(verificationReport.unresolvableRefs)
                verifiedScriptureRefs = rawScriptureRefs.filter {
                    !mismatchRefSet.contains($0) && !unresolvableRefSet.contains($0)
                }
            case .annotateOnMismatch:
                verifiedScriptureRefs = rawScriptureRefs
            }

            let response = BereanContextActionResult(
                id: data["id"] as? String ?? UUID().uuidString,
                action: action,
                title: data["title"] as? String ?? action.title,
                answer: data["answer"] as? String ?? "",
                scriptureReferences: verifiedScriptureRefs,
                suggestedActions: data["suggestedActions"] as? [String] ?? [],
                safetyNotice: data["safetyNotice"] as? String,
                threadId: data["threadId"] as? String,
                constitutionalMode: constitutionResult.requiredMode,
                epistemicDeclaration: verificationReport.epistemicDeclaration
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
