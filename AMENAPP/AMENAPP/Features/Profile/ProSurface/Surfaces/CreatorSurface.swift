import Foundation
import FirebaseFirestore

// MARK: - CreatorSurface

struct CreatorSurface: ProRoleSurface {
    let role: ProRole = .creator
    let priority: Int = 20

    func currentInsight(for userId: String) async -> ProInsight? {
        let startOfToday = Calendar.current.startOfDay(for: Date())

        do {
            let snapshot = try await Firestore.firestore()
                .collection("posts")
                .whereField("authorId", isEqualTo: userId)
                .whereField("createdAt", isGreaterThanOrEqualTo: Timestamp(date: startOfToday))
                .getDocuments()

            guard !snapshot.documents.isEmpty else { return nil }

            // Find the post with the highest playCount (falling back to viewCount)
            let topDoc = snapshot.documents.max { lhs, rhs in
                let lhsCount = lhs.data()["playCount"] as? Int ?? lhs.data()["viewCount"] as? Int ?? 0
                let rhsCount = rhs.data()["playCount"] as? Int ?? rhs.data()["viewCount"] as? Int ?? 0
                return lhsCount < rhsCount
            }

            guard let doc = topDoc else { return nil }
            let data = doc.data()
            let playCount = data["playCount"] as? Int ?? data["viewCount"] as? Int ?? 0

            guard playCount > 0 else { return nil }

            let formatted = formatCount(playCount)
            return ProInsight(
                line: "Your top post today — \(formatted) plays",
                deepLinkPath: "amen://creator-hub"
            )
        } catch {
            return nil
        }
    }

    // MARK: Private Helpers

    private func formatCount(_ count: Int) -> String {
        switch count {
        case 0..<1_000:
            return "\(count)"
        case 1_000..<1_000_000:
            let value = Double(count) / 1_000.0
            let formatted = value.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0fK", value)
                : String(format: "%.1fK", value)
            return formatted
        default:
            let value = Double(count) / 1_000_000.0
            let formatted = value.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0fM", value)
                : String(format: "%.1fM", value)
            return formatted
        }
    }
}
