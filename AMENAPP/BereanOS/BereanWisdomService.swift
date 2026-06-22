import Foundation
import FirebaseFunctions
import FirebaseAuth

// MARK: - Berean Wisdom Service

@MainActor
final class BereanWisdomService: ObservableObject {
    static let shared = BereanWisdomService()

    @Published private(set) var currentAnalysis: BereanWisdomAnalysis?
    @Published private(set) var isAnalyzing = false

    private let functions = Functions.functions()

    private init() {}

    // MARK: - Analyze Decision

    /// Calls the `bereanWisdomAnalysis` Cloud Function to produce a structured
    /// multi-dimension wisdom analysis of the supplied decision question.
    @discardableResult
    func analyzeDecision(
        _ question: String,
        context: String?,
        projectId: String?,
        mode: BereanWisdomMode
    ) async throws -> BereanWisdomAnalysis {
        guard AMENFeatureFlags.shared.bereanOSWisdomEngineEnabled else {
            throw BereanOSError.featureDisabled
        }
        guard Auth.auth().currentUser != nil else {
            throw BereanOSError.unauthorized
        }

        isAnalyzing = true
        defer { isAnalyzing = false }

        var payload: [String: Any] = [
            "question": question,
            "mode": mode.rawValue,
        ]
        if let context = context, !context.isEmpty {
            payload["context"] = context
        }
        if let projectId = projectId {
            payload["projectId"] = projectId
        }

        do {
            let callable = functions.httpsCallable("bereanWisdomAnalysis")
            let result = try await callable.call(payload)

            guard let data = result.data as? [String: Any],
                  let analysisDict = data["analysis"] as? [String: Any] else {
                throw BereanOSError.unknown("Invalid response from server.")
            }

            let analysis = try BereanWisdomAnalysis(from: analysisDict, projectId: projectId, mode: mode)
            currentAnalysis = analysis
            return analysis

        } catch let error as NSError where error.domain == FunctionsErrorDomain {
            let code = FunctionsErrorCode(rawValue: error.code)
            if code == .resourceExhausted {
                throw BereanOSError.rateLimitExceeded
            }
            if let message = error.userInfo[FunctionsErrorDetailsKey] as? String {
                throw BereanOSError.unknown(message)
            }
            throw error
        }
    }

    // MARK: - Clear

    func clearAnalysis() {
        currentAnalysis = nil
    }
}

// MARK: - BereanWisdomAnalysis CF response initializer

private extension BereanWisdomAnalysis {
    init(from dict: [String: Any], projectId: String?, mode: BereanWisdomMode) throws {
        guard let id = dict["id"] as? String,
              let question = dict["question"] as? String else {
            throw BereanOSError.unknown("Malformed analysis response.")
        }

        self.id = id
        self.question = question
        self.projectId = projectId
        self.mode = mode
        self.truthScore = dict["truthScore"] as? Double ?? 0.5
        self.wisdomScore = dict["wisdomScore"] as? Double ?? 0.5
        self.impactSummary = dict["impactSummary"] as? String ?? ""
        self.riskSummary = dict["riskSummary"] as? String ?? ""
        self.stewardshipNotes = dict["stewardshipNotes"] as? String ?? ""
        self.characterImplications = dict["characterImplications"] as? String ?? ""
        self.longTermConsequences = dict["longTermConsequences"] as? String ?? ""
        self.faithPerspective = dict["faithPerspective"] as? String
        self.createdAt = Date()

        let rawPerspectives = dict["perspectives"] as? [[String: Any]] ?? []
        self.perspectives = rawPerspectives.map { p in
            BereanPerspective(
                id: p["id"] as? String ?? UUID().uuidString,
                perspectiveType: p["perspectiveType"] as? String ?? "",
                summary: p["summary"] as? String ?? "",
                agreements: p["agreements"] as? [String] ?? [],
                disagreements: p["disagreements"] as? [String] ?? [],
                tradeoffs: p["tradeoffs"] as? [String] ?? [],
                unknowns: p["unknowns"] as? [String] ?? []
            )
        }
    }
}
