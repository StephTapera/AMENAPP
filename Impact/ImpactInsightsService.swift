import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class ImpactInsightsService: ObservableObject {
    @Published var latestInsight: WeeklyInsight? = nil
    @Published var highlights: [WeeklyInsight.InsightHighlight] = []
    @Published var recommendations: [WeeklyInsight.InsightRecommendation] = []

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    var userId: String? { Auth.auth().currentUser?.uid }

    var weeklySummary: String {
        guard let insight = latestInsight else {
            return "Your weekly impact summary is being prepared."
        }
        var parts: [String] = []
        if insight.summaryTotalGiven > 0 { parts.append("gave $\(insight.summaryTotalGiven / 100) to \(insight.summaryOrganizationsSupported) organization\(insight.summaryOrganizationsSupported == 1 ? "" : "s")") }
        if insight.summaryWellnessHoursLogged > 0 { parts.append(String(format: "logged %.0f wellness hour\(insight.summaryWellnessHoursLogged == 1 ? "" : "s")", insight.summaryWellnessHoursLogged)) }
        if insight.summaryCrisisCheckinsCount > 0 { parts.append("completed \(insight.summaryCrisisCheckinsCount) crisis check-in\(insight.summaryCrisisCheckinsCount == 1 ? "" : "s")") }
        if parts.isEmpty { return "Start your impact journey this week." }
        return "This week you " + parts.joined(separator: ", ") + ". Keep going!"
    }

    func loadLatest() {
        guard let uid = userId else { return }
        listener?.remove()
        listener = db.collection("users").document(uid)
            .collection("insights")
            .whereField("period", isEqualTo: "weekly")
            .order(by: "generatedAt", descending: true)
            .limit(to: 1)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                if let doc = snapshot?.documents.first,
                   let insight = try? doc.data(as: WeeklyInsight.self) {
                    latestInsight = insight
                    highlights = insight.highlights
                    recommendations = insight.recommendations
                }
            }
    }

    deinit { listener?.remove() }
}
