import SwiftUI
import Firebase
import FirebaseFunctions
import Foundation

// MARK: - DigestItemType

enum DigestItemType: String, Codable, Hashable {
    case verse          = "verse"
    case prayerReminder = "prayerReminder"
    case eventToday     = "eventToday"
    case mention        = "mention"
    case bereanStudy    = "bereanStudy"
    case birthday       = "birthday"
    case spaceUpdate    = "spaceUpdate"
    case readingPlan    = "readingPlan"
}

// MARK: - DigestItem

struct DigestItem: Identifiable, Codable {
    let id: String
    let type: DigestItemType
    let title: String
    let body: String?
    let sourceRef: String?
    let priority: Int
    var isRead: Bool
}

// MARK: - AmenDailyDigestViewModel

@MainActor
final class AmenDailyDigestViewModel: ObservableObject {

    @Published var items: [DigestItem] = []
    @Published var greeting: String = ""
    @Published var timeOfDay: String = "morning"
    @Published var isLoading: Bool = false
    @Published var error: String? = nil

    private let functions = Functions.functions(region: "us-central1")
    private let db = Firestore.firestore()

    // MARK: - Load

    func load(userId: String) async {
        guard !userId.isEmpty else { return }
        isLoading = true
        error = nil

        do {
            let result = try await functions
                .httpsCallable("getSpiritualDigest")
                .call(["userId": userId, "forceRefresh": false])

            let raw = result.data as? [String: Any] ?? [:]
            applyResponse(raw)
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Refresh

    func refresh(userId: String) async {
        guard !userId.isEmpty else { return }
        isLoading = true
        error = nil

        do {
            let result = try await functions
                .httpsCallable("getSpiritualDigest")
                .call(["userId": userId, "forceRefresh": true])

            let raw = result.data as? [String: Any] ?? [:]
            applyResponse(raw)
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Mark Read

    func markRead(itemId: String) {
        // Optimistic local update
        if let idx = items.firstIndex(where: { $0.id == itemId }) {
            items[idx].isRead = true
        }

        // Persist to Firestore — fire-and-forget; no userId needed at call site,
        // we pull from the current item's path via itemId only.
        // Path: spiritualOS_digest/{userId}/items/{itemId}
        // The userId is embedded as part of the current user's auth context.
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let ref = db
            .collection("spiritualOS_digest")
            .document(uid)
            .collection("items")
            .document(itemId)

        Task {
            try? await ref.updateData(["isRead": true])
        }
    }

    // MARK: - Private helpers

    private func applyResponse(_ raw: [String: Any]) {
        greeting = raw["greeting"] as? String ?? ""
        timeOfDay = resolvedTimeOfDay(from: raw["timeOfDay"] as? String)

        let rawItems = raw["items"] as? [[String: Any]] ?? []
        items = rawItems.compactMap { dict -> DigestItem? in
            guard
                let id    = dict["id"] as? String,
                let typeStr = dict["type"] as? String,
                let type  = DigestItemType(rawValue: typeStr),
                let title = dict["title"] as? String
            else { return nil }

            return DigestItem(
                id: id,
                type: type,
                title: title,
                body: dict["body"] as? String,
                sourceRef: dict["sourceRef"] as? String,
                priority: dict["priority"] as? Int ?? 0,
                isRead: dict["isRead"] as? Bool ?? false
            )
        }
        .sorted { $0.priority < $1.priority }
    }

    private func resolvedTimeOfDay(from raw: String?) -> String {
        let allowed = ["morning", "afternoon", "evening", "night"]
        guard let value = raw, allowed.contains(value) else {
            let hour = Calendar.current.component(.hour, from: Date())
            switch hour {
            case 5..<12:  return "morning"
            case 12..<17: return "afternoon"
            case 17..<21: return "evening"
            default:      return "night"
            }
        }
        return value
    }
}
