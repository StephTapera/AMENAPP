import Foundation
import FirebaseFirestore
import FirebaseFunctions

@MainActor
final class WellnessLibraryService: ObservableObject {
    @Published var items: [WellnessContent] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let db = Firestore.firestore()
    private let functions = Functions.functions()
    private var listener: ListenerRegistration?

    func fetchItems(category: WellnessCategory? = nil, type: WellnessContentType? = nil, difficulty: WellnessDifficulty? = nil) {
        isLoading = true
        var query: Query = db.collection("wellness")
            .whereField("guardianModerated", isEqualTo: true)
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
        if let cat = category {
            query = query.whereField("category", arrayContains: cat.rawValue)
        }
        if let t = type {
            query = query.whereField("type", isEqualTo: t.rawValue)
        }
        if let d = difficulty {
            query = query.whereField("difficulty", isEqualTo: d.rawValue)
        }
        listener?.remove()
        listener = query.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            isLoading = false
            if let error {
                errorMessage = error.localizedDescription
                return
            }
            items = (snapshot?.documents ?? []).compactMap { doc in
                try? doc.data(as: WellnessContent.self)
            }
        }
    }

    func trackEngagement(wellnessId: String, action: String) {
        Task {
            _ = try? await functions.httpsCallable("trackWellnessEngagement").call([
                "wellnessId": wellnessId,
                "action": action
            ])
        }
    }

    func recommend(context: String) async -> [WellnessContent] {
        do {
            let result = try await functions.httpsCallable("recommendWellnessContent").call(["context": context])
            guard let data = result.data as? [[String: Any]] else { return [] }
            return data.compactMap { dict -> WellnessContent? in
                guard let id = dict["wellnessId"] as? String,
                      let title = dict["title"] as? String,
                      let typeRaw = dict["type"] as? String,
                      let type = WellnessContentType(rawValue: typeRaw),
                      let diffRaw = dict["difficulty"] as? String,
                      let difficulty = WellnessDifficulty(rawValue: diffRaw)
                else { return nil }
                return WellnessContent(id: id, type: type, title: title, description: "", difficulty: difficulty, category: [], tags: [], durationSeconds: nil, steps: nil, body: nil, audioUrl: nil, videoUrl: nil, linkedVerses: nil, engagementViewCount: 0, engagementSavedCount: 0, engagementHelpfulCount: 0, createdAt: nil, guardianModerated: true)
            }
        } catch { return [] }
    }

    deinit { listener?.remove() }
}
