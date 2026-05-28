import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

@MainActor
final class ModerationService: ObservableObject {
    @Published var openCases: [ModerationCase] = []
    @Published var crisisEscalations: [CrisisEscalation] = []
    @Published var isLoading = false

    private let db = Firestore.firestore()
    private let functions = Functions.functions()
    private var casesListener: ListenerRegistration?
    private var escalationsListener: ListenerRegistration?

    func startListening() {
        isLoading = true
        casesListener = db.collection("moderation")
            .whereField("status", in: [ModerationCaseStatus.new.rawValue, ModerationCaseStatus.reviewing.rawValue])
            .order(by: "flag.flaggedAt", descending: true)
            .limit(to: 50)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                isLoading = false
                openCases = (snapshot?.documents ?? []).compactMap { try? $0.data(as: ModerationCase.self) }
            }
        escalationsListener = db.collection("crisisEscalations")
            .whereField("contacted", isEqualTo: false)
            .order(by: "detectedAt", descending: true)
            .limit(to: 20)
            .addSnapshotListener { [weak self] snapshot, _ in
                self?.crisisEscalations = (snapshot?.documents ?? []).compactMap { try? $0.data(as: CrisisEscalation.self) }
            }
    }

    func resolveCase(caseId: String, action: ModerationAction, note: String) async {
        do {
            _ = try await functions.httpsCallable("resolveModerationCase").call([
                "caseId": caseId,
                "action": action.rawValue,
                "notes": note
            ])
        } catch {
            print("Error resolving case: \(error)")
        }
    }

    func markEscalationContacted(escalationId: String, method: String) async {
        try? await db.collection("crisisEscalations").document(escalationId)
            .updateData(["contacted": true, "contactMethod": method, "contactedAt": Timestamp(date: Date())])
    }

    deinit {
        casesListener?.remove()
        escalationsListener?.remove()
    }
}
