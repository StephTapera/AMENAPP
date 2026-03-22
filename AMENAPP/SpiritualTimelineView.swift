// SpiritualTimelineView.swift
// AMENAPP
//
// Spiritual Timeline Generator:
//   - Aggregates user's prayers, church notes, testimonies from Firestore
//   - Calls generateSpiritualTimeline Cloud Function (Claude) → timeline milestones
//   - SwiftUI vertical timeline view with milestone cards
//   - Accessible from Profile or Resources

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// MARK: - Models

struct SpiritualMilestone: Identifiable, Codable {
    let id: UUID
    let date: String             // formatted display date or period e.g. "January 2026"
    let title: String
    let description: String
    let category: MilestoneCategory
    let sourceType: String       // "prayer", "note", "testimony", "journal"

    enum CodingKeys: String, CodingKey {
        case id, date, title, description, category, sourceType
    }

    init(from decoder: Decoder) throws {
        let c    = try decoder.container(keyedBy: CodingKeys.self)
        id          = (try? c.decode(UUID.self,   forKey: .id))          ?? UUID()
        date        = (try? c.decode(String.self, forKey: .date))        ?? ""
        title       = (try? c.decode(String.self, forKey: .title))       ?? ""
        description = (try? c.decode(String.self, forKey: .description)) ?? ""
        category    = (try? c.decode(MilestoneCategory.self, forKey: .category)) ?? .growth
        sourceType  = (try? c.decode(String.self, forKey: .sourceType))  ?? ""
    }
}

enum MilestoneCategory: String, Codable {
    case answered    = "answered_prayer"
    case growth      = "spiritual_growth"
    case challenge   = "challenge"
    case breakthrough = "breakthrough"
    case service     = "service"
    case community   = "community"

    var icon: String {
        switch self {
        case .answered:     return "star.fill"
        case .growth:       return "leaf.fill"
        case .challenge:    return "bolt.fill"
        case .breakthrough: return "sun.max.fill"
        case .service:      return "hands.sparkles.fill"
        case .community:    return "person.3.fill"
        }
    }

    var color: Color {
        switch self {
        case .answered:     return .yellow
        case .growth:       return .green
        case .challenge:    return .orange
        case .breakthrough: return .blue
        case .service:      return .purple
        case .community:    return .teal
        }
    }
}

// MARK: - SpiritualTimelineService

@MainActor
final class SpiritualTimelineService: ObservableObject {
    @Published var milestones: [SpiritualMilestone] = []
    @Published var isLoading  = false
    @Published var error: String?

    private let db        = Firestore.firestore()
    private let functions = Functions.functions()

    func load() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        error     = nil
        defer { isLoading = false }

        // Check Firestore cache (1-week TTL)
        if let cached = await loadCached(uid: uid) {
            milestones = cached
            return
        }

        // Aggregate context
        let context = await gatherContext(uid: uid)
        guard !context.isEmpty else { return }

        // Call Cloud Function
        do {
            let result = try await functions.httpsCallable("generateSpiritualTimeline").call([
                "uid": uid, "context": context
            ])
            guard let data = result.data as? [String: Any],
                  let items = data["milestones"] as? [[String: Any]] else {
                error = "Could not generate timeline."
                return
            }
            milestones = items.compactMap { dict -> SpiritualMilestone? in
                guard let jsonData = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
                return try? JSONDecoder().decode(SpiritualMilestone.self, from: jsonData)
            }
            // Cache for 7 days
            try? await db.collection("users/\(uid)/spiritualTimeline").document("cache")
                .setData([
                    "milestones": items,
                    "generatedAt": FieldValue.serverTimestamp()
                ])
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadCached(uid: String) async -> [SpiritualMilestone]? {
        guard let snap = try? await db.collection("users/\(uid)/spiritualTimeline")
            .document("cache").getDocument(),
              let d = snap.data(),
              let ts = d["generatedAt"] as? Timestamp,
              Date().timeIntervalSince(ts.dateValue()) < 7 * 86400,
              let items = d["milestones"] as? [[String: Any]] else { return nil }

        return items.compactMap { dict -> SpiritualMilestone? in
            guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
            return try? JSONDecoder().decode(SpiritualMilestone.self, from: data)
        }
    }

    private func gatherContext(uid: String) async -> String {
        var parts: [String] = []

        // Last 20 prayers (answered ones weighted higher)
        if let snap = try? await db.collection("prayers")
            .whereField("userId", isEqualTo: uid)
            .order(by: "createdAt", descending: true)
            .limit(to: 20).getDocuments() {
            let prayers = snap.documents.compactMap { doc -> String? in
                guard let text = doc.data()["text"] as? String else { return nil }
                let answered = doc.data()["isAnswered"] as? Bool ?? false
                return answered ? "[ANSWERED] \(text)" : text
            }
            if !prayers.isEmpty {
                parts.append("Prayer journey:\n" + prayers.joined(separator: "\n"))
            }
        }

        // Last 10 church note summaries
        if let snap = try? await db.collection("churchNotes")
            .whereField("userId", isEqualTo: uid)
            .order(by: "date", descending: true)
            .limit(to: 10).getDocuments() {
            let summaries = snap.documents.compactMap { doc -> String? in
                let d = doc.data()
                let title = d["title"] as? String ?? ""
                let kps   = (d["keyPoints"] as? [String] ?? []).prefix(2).joined(separator: "; ")
                return "\(title): \(kps)"
            }
            if !summaries.isEmpty {
                parts.append("Sermon notes:\n" + summaries.joined(separator: "\n"))
            }
        }

        return parts.joined(separator: "\n\n")
    }
}

// MARK: - SpiritualTimelineView

struct SpiritualTimelineView: View {
    @StateObject private var service = SpiritualTimelineService()

    var body: some View {
        Group {
            if service.isLoading {
                loadingState
            } else if let err = service.error {
                errorState(err)
            } else if service.milestones.isEmpty {
                emptyState
            } else {
                timelineContent
            }
        }
        .navigationTitle("Spiritual Timeline")
        .navigationBarTitleDisplayMode(.inline)
        .task { await service.load() }
    }

    private var timelineContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(service.milestones.enumerated()), id: \.element.id) { index, milestone in
                    MilestoneRow(
                        milestone:  milestone,
                        isFirst:    index == 0,
                        isLast:     index == service.milestones.count - 1
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Generating your spiritual timeline…")
                .font(.system(size: 14))
                .foregroundStyle(Color(.secondaryLabel))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40))
                .foregroundStyle(Color(.tertiaryLabel))
            Text("Your timeline will appear here as you add prayers and notes.")
                .font(.system(size: 14))
                .foregroundStyle(Color(.secondaryLabel))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Text(msg)
                .font(.system(size: 14))
                .foregroundStyle(Color(.secondaryLabel))
            Button("Retry") { Task { await service.load() } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - MilestoneRow

private struct MilestoneRow: View {
    let milestone: SpiritualMilestone
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Timeline spine
            VStack(spacing: 0) {
                if !isFirst {
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(width: 2, height: 20)
                } else {
                    Spacer().frame(height: 20)
                }

                // Node dot
                ZStack {
                    Circle()
                        .fill(milestone.category.color.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: milestone.category.icon)
                        .font(.system(size: 14))
                        .foregroundStyle(milestone.category.color)
                }

                if !isLast {
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(width: 2)
                        .frame(minHeight: 40)
                }
            }
            .frame(width: 36)

            // Content card
            VStack(alignment: .leading, spacing: 6) {
                if !milestone.date.isEmpty {
                    Text(milestone.date)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(.tertiaryLabel))
                        .textCase(.uppercase)
                        .padding(.top, 18)
                }
                Text(milestone.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(.label))
                Text(milestone.description)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 20)
            }
        }
    }
}

// MARK: - SpiritualTimelineEntry (entry point — NavigationLink or sheet trigger)

struct SpiritualTimelineEntry: View {
    @State private var showTimeline = false

    var body: some View {
        Button {
            showTimeline = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(.secondaryLabel))
                Text("My Spiritual Timeline")
                    .font(.system(size: 15))
                    .foregroundStyle(Color(.label))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showTimeline) {
            NavigationView {
                SpiritualTimelineView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showTimeline = false }
                        }
                    }
            }
        }
    }
}
