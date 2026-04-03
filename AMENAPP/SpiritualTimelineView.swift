// SpiritualTimelineView.swift
// AMENAPP
//
// Spiritual Timeline Generator:
//   - Aggregates user's prayers, church notes, testimonies from Firestore
//   - Calls generateSpiritualTimeline Cloud Function (Claude) → timeline milestones
//   - SwiftUI vertical timeline view with liquid-glass milestone cards
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

    var glassAccent: Color {
        switch self {
        case .answered:     return Color(hex: "F59E0B")
        case .growth:       return Color(hex: "10B981")
        case .challenge:    return Color(hex: "F97316")
        case .breakthrough: return Color(hex: "06B6D4")
        case .service:      return Color(hex: "6B48FF")
        case .community:    return Color(hex: "8B5CF6")
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
        ZStack {
            Color(hex: "0A0A0F").ignoresSafeArea()

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
        }
        .navigationTitle("Spiritual Timeline")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await service.load() }
    }

    // MARK: Timeline content

    private var timelineContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(service.milestones.enumerated()), id: \.element.id) { index, milestone in
                    MilestoneRow(
                        milestone: milestone,
                        isFirst:   index == 0,
                        isLast:    index == service.milestones.count - 1
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 48)
        }
    }

    // MARK: Loading

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.2)
            Text("Generating your spiritual timeline…")
                .font(AMENFont.regular(14))
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 72, height: 72)
                Image(systemName: "clock.arrow.circlepath")
                    .font(.systemScaled(30, weight: .light))
                    .foregroundColor(.white.opacity(0.4))
            }
            Text("Your timeline will appear here\nas you add prayers and notes.")
                .font(AMENFont.regular(14))
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Error

    private func errorState(_ msg: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.systemScaled(28))
                .foregroundColor(.white.opacity(0.35))
            Text(msg)
                .font(AMENFont.regular(13))
                .foregroundColor(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                Task { await service.load() }
            } label: {
                Text("Retry")
                    .font(AMENFont.semiBold(14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }
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
        HStack(alignment: .top, spacing: 14) {

            // ── Timeline spine + node ──────────────────────────────────────
            VStack(spacing: 0) {
                // Top connector
                if !isFirst {
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 1.5, height: 22)
                } else {
                    Spacer().frame(height: 22)
                }

                // Glass node dot
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                    Circle()
                        .fill(milestone.category.glassAccent.opacity(0.18))
                    Circle()
                        .strokeBorder(milestone.category.glassAccent.opacity(0.45), lineWidth: 1)
                    Image(systemName: milestone.category.icon)
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundColor(milestone.category.glassAccent)
                }
                .frame(width: 36, height: 36)

                // Bottom connector
                if !isLast {
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 1.5)
                        .frame(minHeight: 44)
                }
            }
            .frame(width: 36)

            // ── Glass milestone card ──────────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                if !milestone.date.isEmpty {
                    Text(milestone.date.uppercased())
                        .font(AMENFont.semiBold(10))
                        .foregroundColor(milestone.category.glassAccent.opacity(0.85))
                        .kerning(1.2)
                        .padding(.top, 14)
                }

                Text(milestone.title)
                    .font(AMENFont.semiBold(15))
                    .foregroundColor(.white)

                Text(milestone.description)
                    .font(AMENFont.regular(13))
                    .foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)

                // Source type pill
                if !milestone.sourceType.isEmpty {
                    Text(milestone.sourceType.capitalized)
                        .font(AMENFont.semiBold(10))
                        .foregroundColor(.white.opacity(0.45))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.07))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
            .background(Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.vertical, 8)
        }
    }
}

// MARK: - SpiritualTimelineEntry (liquid glass banner)

struct SpiritualTimelineEntry: View {
    @State private var showTimeline = false

    private let accentGreen = Color(hex: "10B981")
    private let accentGold  = Color(hex: "F59E0B")

    var body: some View {
        Button { showTimeline = true } label: {
            HStack(spacing: 0) {

                // ── Left glass icon panel ────────────────────────────────
                ZStack {
                    // Subtle multi-stop gradient tinted panel
                    LinearGradient(
                        colors: [
                            Color(hex: "10B981").opacity(0.25),
                            Color(hex: "6B48FF").opacity(0.18),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    // Decorative rings
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            .frame(width: 76, height: 76)
                        Circle()
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                            .frame(width: 52, height: 52)
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.systemScaled(26, weight: .light))
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
                .frame(width: 120)

                // ── Right text content ────────────────────────────────────
                VStack(alignment: .leading, spacing: 6) {
                    Text("YOUR JOURNEY")
                        .font(AMENFont.semiBold(9))
                        .kerning(2.0)
                        .foregroundColor(accentGreen.opacity(0.9))

                    Text("Spiritual\nTimeline")
                        .font(AMENFont.bold(20))
                        .foregroundColor(.white)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Label("AI-powered", systemImage: "sparkles")
                            .font(AMENFont.semiBold(10))
                            .foregroundColor(.white.opacity(0.55))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())

                        Label("Milestones", systemImage: "flag.checkered")
                            .font(AMENFont.semiBold(10))
                            .foregroundColor(.white.opacity(0.55))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Text("View my timeline")
                            .font(AMENFont.semiBold(12))
                            .foregroundColor(accentGreen)
                        Image(systemName: "arrow.right")
                            .font(.systemScaled(10, weight: .semibold))
                            .foregroundColor(accentGreen)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 156)
            .background(.ultraThinMaterial)
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(0.04), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(CoCreationPressStyle())
        .sheet(isPresented: $showTimeline) {
            NavigationStack {
                SpiritualTimelineView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showTimeline = false }
                                .font(AMENFont.semiBold(15))
                                .foregroundColor(Color(hex: "6B48FF"))
                        }
                    }
            }
        }
    }
}
