import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Shared types

enum CommunicationScope: String, CaseIterable, Identifiable {
    case all, prayer, study, memory, direct

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:    return "All"
        case .prayer: return "Prayer"
        case .study:  return "Study"
        case .memory: return "Memory"
        case .direct: return "Direct"
        }
    }

    var icon: String {
        switch self {
        case .all:    return "sparkles"
        case .prayer: return "hands.and.sparkles"
        case .study:  return "book.pages"
        case .memory: return "brain.head.profile"
        case .direct: return "message"
        }
    }

    var tint: Color {
        switch self {
        case .all:    return .accentColor
        case .prayer: return .orange
        case .study:  return .blue
        case .memory: return .purple
        case .direct: return .green
        }
    }

    var presenceLabel: String {
        switch self {
        case .all:    return "Active"
        case .prayer: return "Prayer"
        case .study:  return "Studying"
        case .memory: return "Recall"
        case .direct: return "Available"
        }
    }

    static func from(bereanMode: String) -> CommunicationScope {
        switch bereanMode {
        case "prayerSupport": return .prayer
        case "scholarly":     return .study
        case "exploratory":   return .memory
        default:              return .direct
        }
    }
}

struct CommunicationThreadItem: Identifiable {
    let id: String
    let title: String
    let preview: String
    let expandedSummary: String
    let timeLabel: String
    let replyCount: Int
    let needsFollowUp: Bool
    let icon: String
    let tint: Color
    let scope: CommunicationScope
    let presenceLabel: String
    let lastUpdated: Date
}

struct CommunicationPresenceItem: Identifiable {
    let id: String
    let name: String
    let detail: String
    let tint: Color
}

// MARK: - ViewModel

@MainActor
final class BereanCommunicationHubViewModel: ObservableObject {

    enum LoadingState: Equatable {
        case idle, loading, loaded, empty
        case error(String)
    }

    @Published var threads: [CommunicationThreadItem] = []
    @Published var presenceItems: [CommunicationPresenceItem] = []
    @Published var loadingState: LoadingState = .idle
    @Published var digestHeadline = "Berean noticed a few threads worth your attention before the day closes."
    @Published var digestHighlights: [String] = []
    @Published var unresolvedCount = 0

    private var listenerRegistration: ListenerRegistration?

    func load() {
        guard let uid = Auth.auth().currentUser?.uid else {
            loadingState = .error("Sign in to see your threads.")
            return
        }
        loadingState = .loading

        listenerRegistration?.remove()
        listenerRegistration = Firestore.firestore()
            .collection("users").document(uid)
            .collection("bereanConversations")
            .order(by: "lastUpdated", descending: true)
            .limit(to: 20)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    self.loadingState = .error(error.localizedDescription)
                    return
                }
                let items = (snapshot?.documents ?? []).compactMap { Self.threadItem(from: $0) }
                self.threads = items
                self.loadingState = items.isEmpty ? .empty : .loaded
                self.buildPresence(from: items)
                self.buildDigest(from: items)
            }

        Task { await loadUnresolvedCount(uid: uid) }
    }

    func cleanup() {
        listenerRegistration?.remove()
        listenerRegistration = nil
    }

    // MARK: - Private helpers

    private func loadUnresolvedCount(uid: String) async {
        do {
            let snap = try await Firestore.firestore()
                .collection("users").document(uid)
                .collection("churchFollowUps")
                .whereField("followUpStatus", isNotEqualTo: "completed")
                .getDocuments()
            unresolvedCount = snap.documents.count
        } catch {
            unresolvedCount = 0
        }
    }

    private func buildPresence(from items: [CommunicationThreadItem]) {
        let cutoff = Date().addingTimeInterval(-3600)
        let recent = items.filter { $0.lastUpdated > cutoff }

        var result: [CommunicationPresenceItem] = []

        if recent.contains(where: { $0.scope == .prayer }) {
            result.append(.init(id: "prayer", name: "Praying", detail: "Active prayer thread in last hour", tint: .orange))
        }
        if let studyThread = recent.first(where: { $0.scope == .study }) {
            result.append(.init(id: "study", name: "Deep study", detail: "In \(studyThread.title.prefix(30))", tint: .blue))
        }
        if !recent.isEmpty {
            result.append(.init(id: "available", name: "Available", detail: "Open for prayer requests", tint: .green))
        }

        if result.isEmpty {
            result = [
                .init(id: "prayer",    name: "Praying",   detail: "Quiet mode — no active threads", tint: .orange),
                .init(id: "available", name: "Available",  detail: "Open for prayer requests",        tint: .green)
            ]
        }

        presenceItems = result
    }

    private func buildDigest(from items: [CommunicationThreadItem]) {
        var highlights: [String] = []

        if let prayer = items.first(where: { $0.scope == .prayer && $0.needsFollowUp }) {
            highlights.append("A prayer thread \"\(prayer.title.prefix(40))\" still has no follow-up.")
        }
        if let study = items.first(where: { $0.scope == .study }), study.replyCount > 0 {
            highlights.append("Your \(study.title.prefix(30)) has \(study.replyCount) unresolved messages.")
        }
        let memCount = items.filter { $0.scope == .memory }.count
        if memCount > 0 {
            highlights.append("\(memCount) saved reflection\(memCount > 1 ? "s" : "") can be turned into journal entries.")
        }
        if highlights.isEmpty, !items.isEmpty {
            highlights.append("You have \(items.count) active thread\(items.count > 1 ? "s" : "") across prayer, study, and reflection.")
        }
        if highlights.isEmpty {
            highlights = ["No active threads. Start a prayer or study session with Berean."]
        }

        digestHighlights = highlights
    }

    // MARK: - Firestore → Model

    private static func threadItem(from doc: QueryDocumentSnapshot) -> CommunicationThreadItem? {
        let data = doc.data()
        guard let mode = data["mode"] as? String else { return nil }

        let conversationId = (data["conversationId"] as? String) ?? doc.documentID
        let messageCount   = (data["messageCount"] as? Int) ?? 0
        let scope          = CommunicationScope.from(bereanMode: mode)
        let messages       = data["messages"] as? [[String: Any]] ?? []

        let firstUserText  = messages.first(where: { ($0["role"] as? String) == "user" })?["content"] as? String ?? ""
        let lastText       = messages.last?["content"] as? String ?? ""

        let title: String
        if !firstUserText.isEmpty {
            title = String(firstUserText.prefix(55))
        } else {
            switch scope {
            case .prayer: title = "Prayer conversation"
            case .study:  title = "Study session"
            case .memory: title = "Berean reflection"
            default:      title = "Spiritual conversation"
            }
        }

        let preview = lastText.isEmpty ? "Tap to continue this conversation." : String(lastText.prefix(120))

        let expandedSummary: String
        if messages.count >= 3 {
            let midText = messages[messages.count / 2]["content"] as? String ?? ""
            expandedSummary = String(midText.prefix(200))
        } else {
            expandedSummary = String(lastText.prefix(200))
        }

        var lastUpdated = Date()
        if let ts = data["lastUpdated"] as? Timestamp {
            lastUpdated = ts.dateValue()
        }

        return CommunicationThreadItem(
            id:              conversationId,
            title:           title,
            preview:         preview,
            expandedSummary: expandedSummary.isEmpty ? preview : expandedSummary,
            timeLabel:       relativeLabel(from: lastUpdated),
            replyCount:      messageCount,
            needsFollowUp:   scope == .prayer && messageCount > 0,
            icon:            scope.icon,
            tint:            scope.tint,
            scope:           scope,
            presenceLabel:   scope.presenceLabel,
            lastUpdated:     lastUpdated
        )
    }

    private static func relativeLabel(from date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 60    { return "now" }
        if s < 3600  { return "\(s / 60)m" }
        if s < 86400 { return "\(s / 3600)h" }
        return "\(s / 86400)d"
    }
}
