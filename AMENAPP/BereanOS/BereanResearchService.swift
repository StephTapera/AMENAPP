import Foundation
import FirebaseFirestore
import FirebaseFunctions
import FirebaseAuth

// MARK: - BereanResearchService

@MainActor
final class BereanResearchService: ObservableObject {

    // MARK: Singleton
    static let shared = BereanResearchService()

    // MARK: Published state
    @Published private(set) var activeReport: BereanResearchReport?
    @Published private(set) var savedReports: [BereanResearchReport] = []
    @Published private(set) var isResearching: Bool = false
    @Published private(set) var researchStage: String = ""

    // Legacy alias kept for any existing callers
    var recentReports: [BereanResearchReport] { savedReports }

    // MARK: Private
    private let db = Firestore.firestore()
    private let functions = Functions.functions()

    private init() {}

    // MARK: - Public API

    /// Starts a new research run against the `bereanStartResearch` Cloud Function.
    /// - Parameters:
    ///   - query: The research query (min 3 chars enforced server-side).
    ///   - mode: The `BereanResearchMode` to apply.
    ///   - projectId: Optional project scope; if supplied the CF persists the report.
    /// - Returns: The completed `BereanResearchReport`.
    @discardableResult
    func startResearch(
        query: String,
        mode: BereanResearchMode,
        projectId: String?
    ) async throws -> BereanResearchReport {
        guard AMENFeatureFlags.shared.bereanOSResearchEngineEnabled else {
            throw BereanOSError.featureDisabled
        }

        isResearching = true
        activeReport = nil

        defer {
            isResearching = false
            researchStage = ""
        }

        // Stage animation — each stage is displayed for ~1.5 s
        let stages: [String] = [
            "Gathering sources...",
            "Analyzing...",
            "Cross-referencing...",
            "Generating report...",
        ]
        for stage in stages {
            researchStage = stage
            try await Task.sleep(nanoseconds: 1_500_000_000)
        }

        // Call Cloud Function
        let callable = functions.httpsCallable("bereanStartResearch")
        var params: [String: Any] = [
            "query": query,
            "mode": mode.rawValue,
        ]
        if let pid = projectId { params["projectId"] = pid }

        let result = try await callable.call(params)

        guard let data = result.data as? [String: Any],
              let reportDict = data["report"] as? [String: Any] else {
            throw BereanOSError.unknown("Unexpected response from research service.")
        }

        let report = try decodeReport(from: reportDict)
        activeReport = report
        return report
    }

    /// Fetches saved research reports for the given project from Firestore.
    func fetchReports(projectId: String) async throws {
        guard AMENFeatureFlags.shared.bereanOSResearchEngineEnabled else {
            throw BereanOSError.featureDisabled
        }
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let path = BereanOSFirestore.researchReports(uid: uid, projectId: projectId)
        let snapshot = try await db.collection(path)
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .getDocuments()

        savedReports = snapshot.documents.compactMap { doc -> BereanResearchReport? in
            return try? decodeReport(from: doc.data())
        }
    }

    /// Persists the currently active report to Firestore under the given project.
    func saveActiveReport(projectId: String) async throws {
        guard let report = activeReport,
              let uid = Auth.auth().currentUser?.uid else { return }

        let path = BereanOSFirestore.researchReport(
            uid: uid,
            projectId: projectId,
            reportId: report.id
        )
        let encoded = try Firestore.Encoder().encode(report)
        try await db.document(path).setData(encoded)

        if !savedReports.contains(where: { $0.id == report.id }) {
            savedReports.insert(report, at: 0)
        }
    }

    // MARK: - Decoding helper

    private func decodeReport(from dict: [String: Any]) throws -> BereanResearchReport {
        let normalised = normaliseDict(dict)
        let jsonData = try JSONSerialization.data(withJSONObject: normalised)
        return try JSONDecoder.berean.decode(BereanResearchReport.self, from: jsonData)
    }

    /// Recursively converts Firestore Timestamps to ISO-8601 strings.
    private func normaliseDict(_ value: Any) -> Any {
        if let ts = value as? Timestamp {
            return ISO8601DateFormatter().string(from: ts.dateValue())
        }
        if let d = value as? [String: Any] {
            return d.mapValues { normaliseDict($0) }
        }
        if let a = value as? [Any] {
            return a.map { normaliseDict($0) }
        }
        return value
    }
}

// MARK: - JSONDecoder with flexible date strategy

private extension JSONDecoder {
    static let berean: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { dec in
            let container = try dec.singleValueContainer()
            // Number -> epoch seconds (from Firestore Timestamp conversion fallback)
            if let secs = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: secs)
            }
            let str = try container.decode(String.self)
            let formatters: [DateFormatter] = {
                func makeFmt(_ format: String) -> DateFormatter {
                    let f = DateFormatter()
                    f.locale = Locale(identifier: "en_US_POSIX")
                    f.dateFormat = format
                    return f
                }
                return [
                    makeFmt("yyyy-MM-dd'T'HH:mm:ssZ"),
                    makeFmt("yyyy-MM-dd'T'HH:mm:ss.SSSZ"),
                    makeFmt("yyyy-MM-dd'T'HH:mm:ssXXXXX"),
                ]
            }()
            for fmt in formatters {
                if let date = fmt.date(from: str) { return date }
            }
            return Date()
        }
        return decoder
    }()
}
