// CommunityMemoryView.swift — AMEN App
import SwiftUI
import FirebaseFirestore
import FirebaseRemoteConfig

enum DiscussionOutcomeType: String, Codable, Sendable {
    case consensus, question, prayer, insight, unresolved

    var label: String {
        switch self {
        case .consensus:  return "Consensus"
        case .question:   return "Open Question"
        case .prayer:     return "Prayer"
        case .insight:    return "Insight"
        case .unresolved: return "Unresolved"
        }
    }

    var icon: String {
        switch self {
        case .consensus:  return "checkmark.circle"
        case .question:   return "questionmark.circle"
        case .prayer:     return "hands.sparkles"
        case .insight:    return "lightbulb"
        case .unresolved: return "exclamationmark.circle"
        }
    }
}

struct DiscussionOutcome: Identifiable, Codable, Sendable {
    @DocumentID var id: String?
    var threadId: String
    var type: DiscussionOutcomeType
    var summary: String
    var createdAt: Timestamp
}

@MainActor
final class CommunityMemoryService {
    static let shared = CommunityMemoryService()
    private init() {}

    private let db = Firestore.firestore()

    private var isEnabled: Bool {
        RemoteConfig.remoteConfig().configValue(forKey: "discussion_community_memory").boolValue
    }

    func fetchOutcomes(threadId: String) async throws -> [DiscussionOutcome] {
        guard isEnabled else { return [] }
        let snap = try await db.collection("threads").document(threadId)
            .collection("outcomes")
            .order(by: "createdAt", descending: true)
            .limit(to: 10)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: DiscussionOutcome.self) }
    }
}

struct CommunityMemoryView: View {
    let threadId: String
    @State private var outcomes: [DiscussionOutcome] = []
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Community Memory".uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.35))
                .tracking(1.5)

            if isLoading {
                ProgressView()
                    .tint(Color(hex: "#C9A84C"))
                    .scaleEffect(0.8)
            } else if outcomes.isEmpty {
                Text("No outcomes recorded yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.35))
            } else {
                ForEach(outcomes) { outcome in
                    HStack(spacing: 8) {
                        Image(systemName: outcome.type.icon)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: "#C9A84C"))
                        Text(outcome.summary)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.75))
                            .lineLimit(2)
                        Spacer()
                        Text(outcome.type.label)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.white.opacity(0.35))
                    }
                }
            }
        }
        .task {
            isLoading = true
            outcomes = (try? await CommunityMemoryService.shared.fetchOutcomes(threadId: threadId)) ?? []
            isLoading = false
        }
    }
}
