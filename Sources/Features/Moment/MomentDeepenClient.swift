import Foundation
import FirebaseAuth
import FirebaseFunctions
import FirebaseRemoteConfig

@MainActor
public final class AmenMomentDeepenClient {
    public static let shared = AmenMomentDeepenClient()

    private let functions = Functions.functions(region: "us-east1")
    private let remoteConfig = RemoteConfig.remoteConfig()

    private init() {}

    public func flags() -> AmenMomentFlags {
        AmenMomentFlags(
            momentSystemEnabled: remoteConfig.configValue(forKey: "moment_system_enabled").boolValue,
            deepenActionsEnabled: remoteConfig.configValue(forKey: "deepen_actions_enabled").boolValue,
            gatherLiveEnabled: remoteConfig.configValue(forKey: "gather_live_enabled").boolValue,
            gatherComplianceGateCleared: remoteConfig.configValue(forKey: "gather_compliance_gate_cleared").boolValue
        )
    }

    public func runDeepen(
        action: AmenMomentDeepenAction,
        moment: AmenMoment,
        mode: AmenMomentBereanMode,
        saveTarget: AmenMomentSaveTarget? = nil,
        locale: String? = Locale.current.identifier
    ) async throws -> AmenMomentDeepenResult {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AmenMomentClientError.notAuthenticated
        }

        let callable = functions.httpsCallable(functionName(for: action))
        let result = try await callable.call(payload(
            action: action,
            moment: moment,
            requesterId: uid,
            mode: mode,
            saveTarget: saveTarget,
            locale: locale
        ))

        guard let data = result.data as? [String: Any] else {
            throw AmenMomentClientError.invalidResponse
        }

        return try parseResult(data, fallbackAction: action)
    }

    private func functionName(for action: AmenMomentDeepenAction) -> String {
        switch action {
        case .summarize: return "momentSummarize"
        case .crossReference: return "momentCrossReference"
        case .generatePrayer: return "momentGeneratePrayer"
        case .generateStudyGuide: return "momentGenerateStudyGuide"
        case .generateDiscussion: return "momentGenerateDiscussion"
        case .generateDevotional: return "momentGenerateDevotional"
        case .saveTo: return "momentSaveTo"
        }
    }

    private func payload(
        action: AmenMomentDeepenAction,
        moment: AmenMoment,
        requesterId: String,
        mode: AmenMomentBereanMode,
        saveTarget: AmenMomentSaveTarget?,
        locale: String?
    ) -> [String: Any] {
        var body: [String: Any] = [
            "moment": [
                "id": moment.id,
                "type": moment.type.rawValue,
                "temporalState": moment.temporalState.rawValue,
                "refId": moment.refId,
                "ownerId": moment.ownerId,
                "createdAt": NSNumber(value: moment.createdAt)
            ],
            "action": action.rawValue,
            "requesterId": requesterId,
            "bereanMode": mode.rawValue
        ]
        if let saveTarget {
            body["saveTarget"] = saveTarget.rawValue
        }
        if let locale {
            body["locale"] = locale
        }
        return body
    }

    private func parseResult(
        _ data: [String: Any],
        fallbackAction: AmenMomentDeepenAction
    ) throws -> AmenMomentDeepenResult {
        guard let momentId = data["momentId"] as? String else {
            throw AmenMomentClientError.invalidResponse
        }

        let action = (data["action"] as? String).flatMap(AmenMomentDeepenAction.init(rawValue:)) ?? fallbackAction
        let guardian = data["guardian"] as? [String: Any]
        let savedTo = (data["savedTo"] as? String).flatMap(AmenMomentSaveTarget.init(rawValue:))

        return AmenMomentDeepenResult(
            momentId: momentId,
            action: action,
            output: data["output"] as? String ?? "",
            citations: data["citations"] as? [String] ?? [],
            savedTo: savedTo,
            guardianPassed: guardian?["passed"] as? Bool ?? false,
            guardianReason: guardian?["reason"] as? String
        )
    }
}

public enum AmenMomentClientError: LocalizedError {
    case notAuthenticated
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Sign in to deepen this Moment."
        case .invalidResponse:
            return "Moment response was incomplete."
        }
    }
}
