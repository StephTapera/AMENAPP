// PrayerArcCard.swift
// AMENAPP
//
// Prayer Arc — shown on testimony posts that have a linkedPrayerRequestId.
// Sits between the Berean reflect strip and the Conversation section in PostDetailView.
//
// Card shows (in order):
//   1. Berean insight pill (Claude phrase, cached in Firestore)
//   2. Three arc rows: The prayer · The journey · The answer
//   3. Intercessor avatar strip + notification note
//   4. Ask Berean button (pre-seeded with arc context)
//
// Design: white neumorphic card, navy/gold AMEN palette, quiet and smart.

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// MARK: - Post extension (prayer arc helper)

extension Post {
    /// Returns a copy of this Post with prayer arc fields applied.
    func withPrayerArc(
        linkedPrayerRequestId: String?,
        journeyDays: Int?,
        stoneCount: Int?,
        intercessorUids: [String]?,
        bereanArcInsight: String?
    ) -> Post {
        var copy = self
        copy.linkedPrayerRequestId = linkedPrayerRequestId
        copy.journeyDays           = journeyDays
        copy.stoneCount            = stoneCount
        copy.intercessorUids       = intercessorUids
        copy.bereanArcInsight      = bereanArcInsight
        return copy
    }
}

// MARK: - Intercessor profile (lightweight)

struct ArcIntercessor: Identifiable {
    let id: String
    let name: String
    let photoURL: String?
}

// MARK: - PrayerArcViewModel

@MainActor
final class PrayerArcViewModel: ObservableObject {
    @Published var linkedPrayer: Post?
    @Published var intercessors: [ArcIntercessor] = []
    @Published var bereanInsight: String = ""
    @Published var isLoading = true
    @Published var showPrayerDetail = false
    @Published var showIntercessors = false
    @Published var showBerean = false

    private let db         = Firestore.firestore()
    private let functions  = Functions.functions()

    func load(testimonyPost: Post) async {
        guard let linkedId = testimonyPost.linkedPrayerRequestId else {
            isLoading = false
            return
        }

        async let prayerFetch   = fetchLinkedPrayer(linkedId)
        async let insightFetch  = fetchOrGenerateInsight(testimonyPost: testimonyPost)
        async let interFetch    = fetchIntercessors(uids: testimonyPost.intercessorUids ?? [])

        let (prayer, insight, inters) = await (prayerFetch, insightFetch, interFetch)

        linkedPrayer  = prayer
        bereanInsight = insight
        intercessors  = inters
        isLoading     = false
    }

    // MARK: - Firestore fetches

    private func fetchLinkedPrayer(_ postId: String) async -> Post? {
        guard let snap = try? await db.collection("posts").document(postId).getDocument(),
              snap.exists,
              let data = snap.data() else { return nil }
        return postFromFirestore(data: data, id: postId)
    }

    private func fetchIntercessors(uids: [String]) async -> [ArcIntercessor] {
        guard !uids.isEmpty else { return [] }
        var result: [ArcIntercessor] = []
        for uid in uids.prefix(20) {
            if let snap = try? await db.collection("users").document(uid).getDocument(),
               let d = snap.data() {
                result.append(ArcIntercessor(
                    id: uid,
                    name: (d["displayName"] as? String) ?? "A Friend",
                    photoURL: d["profileImageURL"] as? String
                ))
            }
        }
        return result
    }

    // MARK: - Berean insight (cached in Firestore)

    private func fetchOrGenerateInsight(testimonyPost: Post) async -> String {
        guard let postId = testimonyPost.firebaseId else { return "" }
        let cacheRef = db.collection("posts").document(postId)

        // Return cached value if present
        if let insight = testimonyPost.bereanArcInsight, !insight.isEmpty {
            return insight
        }

        // Also check Firestore directly (in case it was set server-side)
        if let snap = try? await cacheRef.getDocument(),
           let cached = snap.data()?["bereanArcInsight"] as? String,
           !cached.isEmpty {
            return cached
        }

        // Generate via Cloud Function
        let days  = testimonyPost.journeyDays ?? 0
        let stones = testimonyPost.stoneCount ?? 0
        guard days > 0 || stones > 0 else { return "" }

        do {
            let result = try await functions.httpsCallable("generateArcInsight").call([
                "days":   days,
                "stones": stones,
                "postId": postId
            ])
            let phrase = (result.data as? [String: Any])?["phrase"] as? String ?? ""
            return phrase
        } catch {
            return ""
        }
    }

    // MARK: - Minimal Firestore → Post mapping (prayer post only)

    private func postFromFirestore(data: [String: Any], id: String) -> Post? {
        guard let content = data["content"] as? String,
              let authorId = data["authorId"] as? String else { return nil }

        let createdAt: Date = {
            if let ts = data["createdAt"] as? Timestamp { return ts.dateValue() }
            return Date()
        }()

        return Post(
            id: UUID(uuidString: id) ?? UUID(),
            firebaseId: id,
            authorId: authorId,
            authorName: (data["authorName"] as? String) ?? "",
            authorUsername: data["authorUsername"] as? String,
            authorInitials: (data["authorInitials"] as? String) ?? "",
            authorProfileImageURL: data["authorProfileImageURL"] as? String,
            timeAgo: "",
            content: content,
            category: .prayer,
            topicTag: nil,
            visibility: .everyone,
            allowComments: true,
            imageURLs: nil,
            linkURL: nil,
            linkPreviewTitle: nil,
            linkPreviewDescription: nil,
            linkPreviewImageURL: nil,
            linkPreviewSiteName: nil,
            linkPreviewType: nil,
            verseReference: nil,
            verseText: nil,
            createdAt: createdAt,
            amenCount: (data["amenCount"] as? Int) ?? 0,
            lightbulbCount: 0,
            commentCount: 0,
            repostCount: 0
        ).withPrayerArc(
            linkedPrayerRequestId: nil,
            journeyDays: nil,
            stoneCount: (data["stoneCount"] as? Int),
            intercessorUids: data["intercessorUids"] as? [String],
            bereanArcInsight: nil
        )
    }
}

// MARK: - PrayerArcCard

struct PrayerArcCard: View {
    let testimonyPost: Post
    @StateObject private var vm = PrayerArcViewModel()
    @State private var bereanQuery = ""

    private let gold  = Color(red: 0.831, green: 0.627, blue: 0.090)
    private let navy  = Color(red: 0.051, green: 0.106, blue: 0.243)

    var body: some View {
        Group {
            if testimonyPost.linkedPrayerRequestId == nil {
                EmptyView()
            } else if vm.isLoading {
                skeletonCard
            } else {
                arcCard
            }
        }
        .task { await vm.load(testimonyPost: testimonyPost) }
        .sheet(isPresented: $vm.showPrayerDetail) {
            if let prayer = vm.linkedPrayer {
                PrayerDetailSheet(prayer: prayer, intercessors: vm.intercessors)
            }
        }
        .sheet(isPresented: $vm.showIntercessors) {
            IntercessorListSheet(intercessors: vm.intercessors,
                                 journeyDays: testimonyPost.journeyDays ?? 0,
                                 stoneCount: testimonyPost.stoneCount ?? 0)
        }
        .fullScreenCover(isPresented: $vm.showBerean) {
            BereanAIAssistantView(initialQuery: bereanQuery.isEmpty ? nil : bereanQuery)
        }
    }

    // MARK: - Arc card

    private var arcCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. Berean insight pill
            if !vm.bereanInsight.isEmpty {
                insightPill(vm.bereanInsight)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
            }

            // 2. Arc rows
            arcRows
                .padding(.horizontal, 16)

            // 3. Intercessor avatars
            if !vm.intercessors.isEmpty {
                avatarStrip
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 4)
            }

            // 4. Ask Berean button
            askBereanButton
                .padding(.top, 14)
                .padding(.bottom, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Insight pill

    private func insightPill(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 14))
                .foregroundStyle(Color(red: 0.18, green: 0.64, blue: 0.40))
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Color(.label))
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(
            LinearGradient(
                colors: [Color(red: 0.22, green: 0.80, blue: 0.52).opacity(0.15),
                         Color(red: 0.20, green: 0.60, blue: 0.86).opacity(0.15)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: Capsule()
        )
    }

    // MARK: - Arc rows

    private var arcRows: some View {
        VStack(spacing: 0) {
            // Row 1 — The prayer
            arcRow(
                icon: "hands.sparkles",
                label: String((vm.linkedPrayer?.content ?? "").prefix(60)),
                hasChevron: true,
                isGold: false
            ) {
                vm.showPrayerDetail = true
            }

            rowDivider

            // Row 2 — The journey
            let days   = testimonyPost.journeyDays ?? 0
            let stones = testimonyPost.stoneCount ?? 0
            arcRow(
                icon: "calendar.badge.clock",
                label: "\(days) day\(days == 1 ? "" : "s") · \(stones) \(stones == 1 ? "person" : "people") prayed",
                hasChevron: true,
                isGold: false
            ) {
                vm.showIntercessors = true
            }

            rowDivider

            // Row 3 — The answer (this testimony)
            arcRow(
                icon: "checkmark.seal",
                label: String(testimonyPost.content.prefix(60)),
                hasChevron: false,
                isGold: true,
                action: nil
            )
        }
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(.systemGray5), lineWidth: 0.5)
        )
    }

    private func arcRow(
        icon: String,
        label: String,
        hasChevron: Bool,
        isGold: Bool,
        action: (() -> Void)? = nil
    ) -> some View {
        let rowContent = HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(isGold ? gold : Color(.secondaryLabel))
            }
            Text(label.isEmpty ? "—" : label + (label.count >= 60 ? "…" : ""))
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color(.label))
                .lineLimit(1)
            Spacer()
            if hasChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 52)

        if let action = action {
            return AnyView(
                Button(action: action) { rowContent }
                    .buttonStyle(.plain)
            )
        } else {
            return AnyView(rowContent)
        }
    }

    private var rowDivider: some View {
        Divider()
            .frame(height: 0.5)
            .background(Color(.systemGray5))
            .padding(.leading, 64)
    }

    // MARK: - Avatar strip

    private var avatarStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: -6) {
                ForEach(vm.intercessors.prefix(5)) { person in
                    AsyncImage(url: URL(string: person.photoURL ?? "")) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFill()
                        } else {
                            Circle().fill(Color(.systemGray4))
                        }
                    }
                    .frame(width: 24, height: 24)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                }
                if vm.intercessors.count > 5 {
                    ZStack {
                        Circle().fill(Color(.systemGray5))
                        Text("+\(vm.intercessors.count - 5)")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                }
            }
            Text("\(vm.intercessors.count) \(vm.intercessors.count == 1 ? "person" : "people") received a notification today")
                .font(.system(size: 11))
                .foregroundStyle(Color(.tertiaryLabel))
        }
    }

    // MARK: - Ask Berean button

    private var askBereanButton: some View {
        VStack(spacing: 6) {
            Button {
                let days   = testimonyPost.journeyDays ?? 0
                let stones = testimonyPost.stoneCount ?? 0
                let cat    = testimonyPost.category.displayName
                let text   = String(testimonyPost.content.prefix(300))
                bereanQuery = "The user is reading a testimony about \(cat). The prayer lasted \(days) days. \(stones) people interceded. The testimony text is: \(text). Answer questions about this spiritual journey with warmth and Scripture. Keep responses brief."
                vm.showBerean = true
            } label: {
                ZStack {
                    Circle()
                        .fill(Color(.systemBackground))
                        .frame(width: 52, height: 52)
                        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 2)
                    Image("amen-logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 26, height: 26)
                        .blendMode(.multiply)
                }
            }
            .buttonStyle(.plain)
            Text("ask anything...")
                .font(.system(size: 12))
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Skeleton

    private var skeletonCard: some View {
        VStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(height: 20)
                    .shimmer()
            }
        }
        .padding(20)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}

// MARK: - PrayerDetailSheet

private struct PrayerDetailSheet: View {
    let prayer: Post
    let intercessors: [ArcIntercessor]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(prayer.content)
                        .font(.system(size: 16))
                        .foregroundStyle(Color(.label))
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                    if !intercessors.isEmpty {
                        Divider().padding(.horizontal, 20)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("People who prayed")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(.secondaryLabel))
                                .padding(.horizontal, 20)
                            ForEach(intercessors) { person in
                                HStack(spacing: 12) {
                                    AsyncImage(url: URL(string: person.photoURL ?? "")) { phase in
                                        if let img = phase.image { img.resizable().scaledToFill() }
                                        else { Circle().fill(Color(.systemGray4)) }
                                    }
                                    .frame(width: 32, height: 32)
                                    .clipShape(Circle())
                                    Text(person.name)
                                        .font(.system(size: 15))
                                        .foregroundStyle(Color(.label))
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                    }
                }
            }
            .navigationTitle("The Prayer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - IntercessorListSheet

private struct IntercessorListSheet: View {
    let intercessors: [ArcIntercessor]
    let journeyDays: Int
    let stoneCount: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List(intercessors) { person in
                HStack(spacing: 12) {
                    AsyncImage(url: URL(string: person.photoURL ?? "")) { phase in
                        if let img = phase.image { img.resizable().scaledToFill() }
                        else { Circle().fill(Color(.systemGray4)) }
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                    Text(person.name)
                        .font(.system(size: 15))
                        .foregroundStyle(Color(.label))
                }
            }
            .listStyle(.plain)
            .navigationTitle("\(journeyDays) days · \(stoneCount) people")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Shimmer modifier (reused from app)

private extension View {
    @ViewBuilder
    func shimmer() -> some View {
        self.overlay(
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(0.4), location: 0.5),
                    .init(color: .clear, location: 1),
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
            .mask(self)
        )
    }
}
