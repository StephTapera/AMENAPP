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

// MARK: - SpiritualTimelineEntry (smart banner entry point)

struct SpiritualTimelineEntry: View {
    @State private var showTimeline = false

    // Deep forest/emerald palette — calm, growth-oriented
    private let emerald  = Color(red: 0.10, green: 0.47, blue: 0.30)
    private let emeraldD = Color(red: 0.06, green: 0.28, blue: 0.18)

    var body: some View {
        Button { showTimeline = true } label: {
            HStack(spacing: 0) {
                // ── Left panel: gradient + icon ─────────────────────────────
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(
                        stops: [
                            .init(color: Color(red: 0.10, green: 0.47, blue: 0.30), location: 0.0),
                            .init(color: Color(red: 0.07, green: 0.36, blue: 0.22), location: 0.55),
                            .init(color: Color(red: 0.06, green: 0.28, blue: 0.18), location: 1.0),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    // Decorative orbit rings
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            .frame(width: 80, height: 80)
                        Circle()
                            .stroke(Color.white.opacity(0.07), lineWidth: 1)
                            .frame(width: 56, height: 56)
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(Color.white.opacity(0.90))
                    }
                    .padding(.leading, 24)
                    .padding(.bottom, 20)
                }
                .frame(width: 130)

                // ── Right panel: white editorial ─────────────────────────────
                VStack(alignment: .leading, spacing: 6) {
                    Text("YOUR JOURNEY")
                        .font(.system(size: 9, weight: .semibold))
                        .kerning(2.0)
                        .foregroundStyle(emerald)

                    Text("Spiritual\nTimeline")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)

                    HStack(spacing: 6) {
                        Label("AI-powered", systemImage: "sparkles")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color(.secondaryLabel))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.thinMaterial, in: Capsule())
                        Label("Milestones", systemImage: "flag.checkered")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color(.secondaryLabel))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.thinMaterial, in: Capsule())
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Text("View my timeline")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(emerald)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(emerald)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemBackground))
            }
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: emerald.opacity(0.20), radius: 18, x: 0, y: 8)
            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
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
