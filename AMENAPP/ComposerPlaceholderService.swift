import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Resolves the best contextual placeholder for the post composer.
/// Priority: activity signals → time/day → post category → generic fallback.
/// Result is cached per session so it never flickers mid-session.
final class ComposerPlaceholderService {
    static let shared = ComposerPlaceholderService()
    private init() {}

    private var cached: String?
    private lazy var db = Firestore.firestore()

    private let genericFallbacks = [
        "What's on your heart?",
        "Something worth sharing?",
        "What are you thinking about?",
        "Got something on your mind?",
        "What's stirring in you today?"
    ]

    func getPlaceholder(for userId: String) async -> String {
        if let hit = cached { return hit }
        let result = await resolve(userId: userId)
        cached = result
        return result
    }

    func resetCache() { cached = nil }

    // MARK: - Resolution

    private func resolve(userId: String) async -> String {
        // 1. Activity signals (Firestore)
        if let activity = await activityBased(userId: userId) { return activity }
        // 2. Time / day
        if let timed = timeBased() { return timed }
        // 3. Post category
        if let category = await categoryBased(userId: userId) { return category }
        // 4. Generic
        return genericFallbacks.randomElement()!
    }

    // MARK: - Activity signals

    private func activityBased(userId: String) async -> String? {
        async let echoCheck   = recentEchoOnPost(userId: userId)
        async let joinDate    = userJoinDate(userId: userId)
        async let unanswered  = hasUnansweredPrayer(userId: userId)
        async let recentComment = hasRecentComment(userId: userId)

        if await echoCheck    { return "Someone's standing with you in prayer..." }
        // A8-007: inactivity-based branch removed — absence reminders on composer open cause guilt pressure.
        if let jd = await joinDate, daysSince(jd) < 7  { return "What's something you're thinking about?" }
        if await unanswered   { return "Still believing for something?" }
        if await recentComment { return "You've got people engaging — share something new" }
        return nil
    }

    private func recentEchoOnPost(userId: String) async -> Bool {
        // Note: This query requires a composite index: authorId + lastEchoAt
        // If index is missing, gracefully return false instead of crashing
        let cutoff = Timestamp(date: Date().addingTimeInterval(-86400 * 3)) // last 3 days
        do {
            let snap = try await db.collection("posts")
                .whereField("authorId", isEqualTo: userId)
                .whereField("lastEchoAt", isGreaterThan: cutoff)
                .limit(to: 1)
                .getDocuments()
            return !snap.documents.isEmpty
        } catch {
            // Gracefully handle missing index error
            print("⚠️ [ComposerPlaceholder] recentEchoOnPost query failed (likely missing index): \(error)")
            return false
        }
    }

    private func lastPostDate(userId: String) async -> Date? {
        let snap = try? await db.collection("posts")
            .whereField("authorId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: 1)
            .getDocuments()
        guard let doc = snap?.documents.first,
              let ts = doc.data()["createdAt"] as? Timestamp else { return nil }
        return ts.dateValue()
    }

    private func userJoinDate(userId: String) async -> Date? {
        let doc = try? await db.collection("users").document(userId).getDocument()
        guard let ts = doc?.data()?["createdAt"] as? Timestamp else { return nil }
        return ts.dateValue()
    }

    private func hasUnansweredPrayer(userId: String) async -> Bool {
        let snap = try? await db.collection("posts")
            .whereField("authorId", isEqualTo: userId)
            .whereField("category", isEqualTo: "prayer")
            .whereField("answered", isEqualTo: false)
            .limit(to: 1)
            .getDocuments()
        return (snap?.documents.isEmpty == false)
    }

    private func hasRecentComment(userId: String) async -> Bool {
        // Note: This query requires a composite index: authorId + lastCommentAt
        // If index is missing, gracefully return false instead of crashing
        let cutoff = Timestamp(date: Date().addingTimeInterval(-86400 * 2))
        do {
            let snap = try await db.collection("posts")
                .whereField("authorId", isEqualTo: userId)
                .whereField("lastCommentAt", isGreaterThan: cutoff)
                .limit(to: 1)
                .getDocuments()
            return !snap.documents.isEmpty
        } catch {
            // Gracefully handle missing index error
            print("⚠️ [ComposerPlaceholder] hasRecentComment query failed (likely missing index): \(error)")
            return false
        }
    }

    // MARK: - Time / day

    private func timeBased() -> String? {
        let cal  = Calendar.current
        let now  = Date()
        let hour = cal.component(.hour, from: now)
        let weekday = cal.component(.weekday, from: now) // 1=Sun, 2=Mon ... 7=Sat

        if weekday == 1 {
            if (6..<12).contains(hour) { return "What's God saying to you today?" }
            if (12..<18).contains(hour) { return "What stood out from the message today?" }
        }
        if weekday == 2 { return "New week — what are you carrying into it?" }
        if weekday == 6 && hour >= 17 { return "What's wrapping up well this week?" }
        if (5..<8).contains(hour) { return "Early riser — what's on your mind this morning?" }
        if hour >= 21 { return "Late night thoughts..." }
        return nil
    }

    // MARK: - Category-based

    private func categoryBased(userId: String) async -> String? {
        let snap = try? await db.collection("posts")
            .whereField("authorId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: 20)
            .getDocuments()
        guard let docs = snap?.documents, !docs.isEmpty else { return nil }

        var counts: [String: Int] = [:]
        for doc in docs {
            if let cat = doc.data()["category"] as? String {
                counts[cat, default: 0] += 1
            }
        }
        guard let top = counts.max(by: { $0.value < $1.value })?.key else { return nil }

        switch top {
        case "tech":      return "Anything in the tech world worth discussing?"
        case "theology":  return "What truth are you sitting with lately?"
        case "ethics":    return "Got a question worth wrestling with?"
        default:          return "What's something worth sharing today?"
        }
    }

    // MARK: - Helpers

    private func daysSince(_ date: Date) -> Int {
        Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
    }
}
