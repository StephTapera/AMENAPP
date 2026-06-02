import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Covenant Discovery View
// Discovery feed for finding creator communities (Covenants).
// Calm, premium, Apple-native aesthetic — not Discord, not generic Patreon.

struct AmenCovenantDiscoveryView: View {
    @EnvironmentObject var vm: AmenCovenantViewModel
    @StateObject private var discoverVM = AmenCovenantDiscoveryViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSearch = false

    private let categories = ["All", "Teaching", "Prayer", "Bible Study", "Worship", "Ministry", "Local Church", "Youth"]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // 1. Glass search capsule
                searchBar
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                // 2. Category chips
                categoryChips
                    .padding(.bottom, 24)

                if discoverVM.isLoading {
                    loadingState
                } else {
                    // 3. Based on your memberships
                    if !discoverVM.yourCreators.isEmpty {
                        sectionHeader("Based on Your Memberships")
                        yourCreatorsRail
                            .padding(.bottom, 28)
                    }

                    // 4. Creators for You — vertical large cards
                    if !discoverVM.featuredCreators.isEmpty {
                        sectionHeader("Creators for You")
                        featuredCreatorsList
                            .padding(.bottom, 28)
                    }

                    // 5. Popular this week — horizontal compact
                    if !discoverVM.popularCreators.isEmpty {
                        sectionHeader("Popular This Week")
                        popularCreatorsRail
                            .padding(.bottom, 28)
                    }

                    // 6. New Teaching Series
                    sectionHeader("New Teaching Series")
                    teachingSeriesRail
                        .padding(.bottom, 40)
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .task { await discoverVM.load() }
        .sheet(isPresented: $showSearch) {
            AmenCovenantSearchView()
        }
        .navigationTitle("Discover")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        Button {
            showSearch = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Search communities…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: Color.black.opacity(0.08), radius: 14, y: 6)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search communities")
    }

    // MARK: - Category Chips

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { category in
                    CovenantDiscoveryCategoryChip(
                        label: category,
                        isSelected: discoverVM.selectedCategory == category,
                        reduceMotion: reduceMotion
                    ) {
                        withAnimation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.75)) {
                            discoverVM.selectedCategory = category
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.bold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
    }

    // MARK: - Your Creators Rail (compact rows, horizontal)

    private var yourCreatorsRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(discoverVM.yourCreators.prefix(3)) { creator in
                    CompactCreatorRow(creator: creator) {
                        vm.navigate(to: .creatorHub(creatorId: creator.id))
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Featured Creators List (large vertical cards)

    private var featuredCreatorsList: some View {
        VStack(spacing: 14) {
            ForEach(discoverVM.featuredCreators) { creator in
                LargeCreatorCard(creator: creator) {
                    vm.navigate(to: .creatorHub(creatorId: creator.id))
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Popular Creators Rail (compact horizontal)

    private var popularCreatorsRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(discoverVM.popularCreators) { creator in
                    PopularCreatorCard(creator: creator) {
                        vm.navigate(to: .creatorHub(creatorId: creator.id))
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Teaching Series Rail

    private var teachingSeriesRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(TeachingSeriesPlaceholder.seeds) { item in
                    TeachingSeriesCard(item: item)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Finding communities…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Category Chip

private struct CovenantDiscoveryCategoryChip: View {
    let label: String
    let isSelected: Bool
    let reduceMotion: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.purple : Color(uiColor: .secondarySystemGroupedBackground))
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Large Creator Card

private struct LargeCreatorCard: View {
    let creator: AmenCovenantDiscoveryViewModel.DiscoveryCreatorItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // Banner
                ZStack(alignment: .bottomLeading) {
                    AsyncImage(url: URL(string: creator.avatarURL ?? "")) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        LinearGradient(
                            colors: [Color.purple.opacity(0.35), Color.indigo.opacity(0.35)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .clipped()
                    .overlay(
                        LinearGradient(
                            colors: [.clear, Color.black.opacity(0.35)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // Avatar overlay
                    AsyncImage(url: URL(string: creator.avatarURL ?? "")) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.purple.opacity(0.3)
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .offset(x: 16, y: 22)
                }

                // Content
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(creator.displayName)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text("@\(creator.handle)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        memberCountBadge(creator.memberCount)
                    }
                    .padding(.top, 28)

                    if !creator.topics.isEmpty {
                        topicChips(creator.topics)
                    }

                    if !creator.badges.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(creator.badges.prefix(3), id: \.self) { badge in
                                AmenTrustBadge(type: badge, size: .compact)
                            }
                        }
                    }

                    HStack {
                        Text(joinLabel(creator))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(Color.purple))

                        Spacer()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: Color.black.opacity(0.08), radius: 14, y: 6)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(creator.displayName), \(joinLabel(creator))")
    }

    private func memberCountBadge(_ count: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(formatCount(count))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func topicChips(_ topics: [String]) -> some View {
        HStack(spacing: 6) {
            ForEach(topics.prefix(3), id: \.self) { topic in
                Text(topic)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Color.purple.opacity(0.1))
                    )
            }
        }
    }

    private func joinLabel(_ creator: AmenCovenantDiscoveryViewModel.DiscoveryCreatorItem) -> String {
        if let price = creator.tierStartingPrice, price > 0 {
            let fmt = NumberFormatter()
            fmt.numberStyle = .currency
            fmt.currencyCode = "USD"
            fmt.maximumFractionDigits = 0
            let s = fmt.string(from: NSNumber(value: price)) ?? "$\(Int(price))"
            return "Join from \(s)/mo"
        }
        return "Join Free"
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000 {
            return String(format: "%.1fk", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

// MARK: - Compact Creator Row (horizontal rail)

private struct CompactCreatorRow: View {
    let creator: AmenCovenantDiscoveryViewModel.DiscoveryCreatorItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: creator.avatarURL ?? "")) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.purple.opacity(0.2)
                }
                .frame(width: 46, height: 46)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(creator.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(creator.tagline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text(formatCount(creator.memberCount))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer(minLength: 8)

                Text("Join")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .stroke(Color.purple.opacity(0.5), lineWidth: 1)
                    )
            }
            .padding(14)
            .frame(width: 300)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: Color.black.opacity(0.06), radius: 8, y: 3)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(creator.displayName), \(creator.tagline)")
    }

    private func formatCount(_ count: Int) -> String {
        count >= 1_000 ? String(format: "%.1fk", Double(count) / 1_000) : "\(count)"
    }
}

// MARK: - Popular Creator Card (compact horizontal card)

private struct PopularCreatorCard: View {
    let creator: AmenCovenantDiscoveryViewModel.DiscoveryCreatorItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                AsyncImage(url: URL(string: creator.avatarURL ?? "")) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.purple.opacity(0.2)
                }
                .frame(width: 52, height: 52)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.purple.opacity(0.2), lineWidth: 1))

                VStack(alignment: .leading, spacing: 3) {
                    Text(creator.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("@\(creator.handle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !creator.badges.isEmpty {
                    AmenTrustBadge(type: creator.badges[0], size: .compact)
                }
            }
            .padding(14)
            .frame(width: 140)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: Color.black.opacity(0.06), radius: 8, y: 3)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(creator.displayName)
    }
}

// MARK: - Teaching Series Placeholder Model + Card

struct TeachingSeriesPlaceholder: Identifiable {
    let id: String
    let title: String
    let creatorName: String
    let scriptureRef: String
    let postType: String

    static let seeds: [TeachingSeriesPlaceholder] = [
        .init(id: "1", title: "The Sermon on the Mount", creatorName: "David Okafor", scriptureRef: "Matthew 5-7", postType: "Teaching"),
        .init(id: "2", title: "Rooted in Grace", creatorName: "Pastor Amara", scriptureRef: "Romans 8", postType: "Series"),
        .init(id: "3", title: "Walking in the Spirit", creatorName: "Covenant Light", scriptureRef: "Galatians 5", postType: "Devotional"),
        .init(id: "4", title: "The Psalms of Ascent", creatorName: "Mount Zion Church", scriptureRef: "Psalm 120-134", postType: "Study"),
    ]
}

private struct TeachingSeriesCard: View {
    let item: TeachingSeriesPlaceholder

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(item.postType)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.purple.opacity(0.1)))

                Spacer()
            }

            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            Text(item.creatorName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 5) {
                Image(systemName: "book.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.indigo)
                Text(item.scriptureRef)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.indigo)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Color.indigo.opacity(0.08))
            )
        }
        .padding(16)
        .frame(width: 200)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.06), radius: 8, y: 3)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title) by \(item.creatorName), \(item.scriptureRef)")
    }
}

// MARK: - Discovery View Model

@MainActor
final class AmenCovenantDiscoveryViewModel: ObservableObject {
    @Published var selectedCategory: String = "All"
    @Published var featuredCreators: [DiscoveryCreatorItem] = []
    @Published var yourCreators: [DiscoveryCreatorItem] = []
    @Published var popularCreators: [DiscoveryCreatorItem] = []
    @Published var isLoading: Bool = false

    struct DiscoveryCreatorItem: Identifiable {
        let id: String
        let displayName: String
        let handle: String
        let tagline: String
        let avatarURL: String?
        let topics: [String]
        let badges: [TrustBadgeType]
        let memberCount: Int
        let tierStartingPrice: Double?
        let covenantId: String
    }

    private let db = Firestore.firestore()

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Load all public, non-paused covenants ordered by memberCount, limit 20
            let snap = try await db.collection("covenants")
                .whereField("isPublic", isEqualTo: true)
                .whereField("isPaused", isEqualTo: false)
                .order(by: "memberCount", descending: true)
                .limit(to: 20)
                .getDocuments()

            let all = snap.documents.compactMap { doc -> DiscoveryCreatorItem? in
                let data = doc.data()
                return DiscoveryCreatorItem(
                    id: doc.documentID,
                    displayName: data["name"] as? String ?? "Unknown",
                    handle: data["handle"] as? String ?? doc.documentID,
                    tagline: data["tagline"] as? String ?? "",
                    avatarURL: data["avatarURL"] as? String,
                    topics: data["topics"] as? [String] ?? [],
                    badges: (data["trustBadges"] as? [String] ?? []).compactMap { TrustBadgeType(rawValue: $0) },
                    memberCount: data["memberCount"] as? Int ?? 0,
                    tierStartingPrice: lowestTierPrice(from: data),
                    covenantId: doc.documentID
                )
            }

            // Popular = top 6 by member count (already sorted)
            popularCreators = Array(all.prefix(6))

            // Featured = next slab, up to 5
            featuredCreators = Array(all.dropFirst(6).prefix(5))

            // "Based on memberships" — load user's joined covenants and suggest similar
            if let uid = Auth.auth().currentUser?.uid {
                let memberSnap = try await db.collection("covenantMemberships")
                    .whereField("userId", isEqualTo: uid)
                    .whereField("status", in: ["active", "trialing"])
                    .limit(to: 5)
                    .getDocuments()
                let joinedIds = Set(memberSnap.documents.compactMap { $0.data()["covenantId"] as? String })

                // Suggest creators not already joined, take first 3
                yourCreators = Array(all.filter { !joinedIds.contains($0.id) }.prefix(3))
            }

        } catch {
            // Non-fatal: leave arrays empty, UI handles gracefully
        }
    }

    // MARK: - Helpers

    private func lowestTierPrice(from data: [String: Any]) -> Double? {
        guard let tiers = data["tiers"] as? [[String: Any]] else { return nil }
        let prices = tiers.compactMap { $0["price"] as? Double }.filter { $0 > 0 }
        return prices.min()
    }
}
