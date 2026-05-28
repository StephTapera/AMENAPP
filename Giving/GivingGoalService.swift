import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

@MainActor
final class GivingGoalService: ObservableObject {
    @Published var goals: [GivingGoal] = []
    @Published var isLoading = false

    private let db = Firestore.firestore()
    private let functions = Functions.functions()
    private var listener: ListenerRegistration?

    var userId: String? { Auth.auth().currentUser?.uid }

    func startListening() {
        guard let uid = userId else { return }
        isLoading = true
        listener = db.collection("users").document(uid)
            .collection("givingGoals")
            .whereField("status", in: ["active", "paused"])
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                isLoading = false
                goals = (snapshot?.documents ?? []).compactMap { try? $0.data(as: GivingGoal.self) }
            }
    }

    func createGoal(title: String, targetAmount: Int?, targetCount: Int?, organizations: [String], frequency: GoalFrequency, reminderFrequency: ReminderFrequency) async throws {
        guard let uid = userId else { return }
        var params: [String: Any] = [
            "userId": uid,
            "title": title,
            "organizations": organizations,
            "frequency": frequency.rawValue,
            "reminderFrequency": reminderFrequency.rawValue
        ]
        if let amount = targetAmount { params["targetAmount"] = amount }
        if let count = targetCount { params["targetCount"] = count }
        _ = try await functions.httpsCallable("createGivingGoal").call(params)
    }

    func completedGoals() async -> [GivingGoal] {
        guard let uid = userId else { return [] }
        let snap = try? await db.collection("users").document(uid)
            .collection("givingGoals")
            .whereField("status", isEqualTo: "completed")
            .order(by: "createdAt", descending: true)
            .getDocuments()
        return (snap?.documents ?? []).compactMap { try? $0.data(as: GivingGoal.self) }
    }

    deinit { listener?.remove() }
}
