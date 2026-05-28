import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

@MainActor
final class WellnessStreakService: ObservableObject {
    @Published var streaks: [WellnessStreak] = []
    @Published var journalEntries: [WellnessJournalEntry] = []
    @Published var isLoading = false

    private let db = Firestore.firestore()
    private let functions = Functions.functions()
    private var streakListener: ListenerRegistration?
    private var journalListener: ListenerRegistration?

    var userId: String? { Auth.auth().currentUser?.uid }

    func startListening() {
        guard let uid = userId else { return }
        isLoading = true
        streakListener = db.collection("users").document(uid)
            .collection("wellnessStreaks")
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                isLoading = false
                streaks = (snapshot?.documents ?? []).compactMap { try? $0.data(as: WellnessStreak.self) }
            }
    }

    func loadJournalEntries(month: Date = Date()) {
        guard let uid = userId else { return }
        let start = Calendar.current.startOfMonth(for: month)
        let end = Calendar.current.endOfMonth(for: month)
        journalListener?.remove()
        journalListener = db.collection("users").document(uid)
            .collection("wellnessJournal")
            .whereField("date", isGreaterThan: Timestamp(date: start))
            .whereField("date", isLessThan: Timestamp(date: end))
            .order(by: "date", descending: true)
            .addSnapshotListener { [weak self] snapshot, _ in
                self?.journalEntries = (snapshot?.documents ?? []).compactMap { try? $0.data(as: WellnessJournalEntry.self) }
            }
    }

    func logActivity(type: WellnessStreakType, wellnessId: String, duration: Int) async {
        guard let uid = userId else { return }
        _ = try? await functions.httpsCallable("logWellnessActivity").call([
            "userId": uid,
            "activityType": type.rawValue,
            "wellnessId": wellnessId,
            "duration": duration
        ])
    }

    func saveJournalEntry(_ entry: WellnessJournalEntry) async {
        guard let uid = userId else { return }
        _ = try? await functions.httpsCallable("createWellnessJournalEntry").call([
            "userId": uid,
            "date": Timestamp(date: Date()),
            "entry": entry.entry,
            "mood": entry.mood?.rawValue ?? "",
            "shared": entry.shared
        ])
    }

    func nextBadge(for streak: WellnessStreak) -> StreakBadge? {
        StreakBadge.all.first { !streak.badges.contains($0.id) && $0.daysRequired > streak.currentStreak }
    }

    deinit {
        streakListener?.remove()
        journalListener?.remove()
    }
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let comps = dateComponents([.year, .month], from: date)
        return self.date(from: comps) ?? date
    }
    func endOfMonth(for date: Date) -> Date {
        guard let start = self.date(from: dateComponents([.year, .month], from: date)),
              let end = self.date(byAdding: DateComponents(month: 1, day: -1), to: start)
        else { return date }
        return end
    }
}
