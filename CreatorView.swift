
//
//  CreatorView.swift
//  AMENAPP
//
//  Creator ecosystem — faith creator profiles, teaching series,
//  devotional content, tip jar, and subscriptions.
//

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Data Models

struct FaithCreator: Identifiable, Codable {
    var id: String = UUID().uuidString
    var displayName: String
    var handle: String
    var bio: String
    var avatarURL: String
    var bannerColor: String       // hex string for gradient base
    var category: CreatorCategory
    var specialties: [String]
    var subscriberCount: Int
    var isVerified: Bool
    var tipJarEnabled: Bool
    var subscriptionPrice: Double // 0 = free
    var totalContent: Int
    var featuredSeries: String
    var socialLinks: [String: String]
    var createdAt: Date
}

enum CreatorCategory: String, Codable, CaseIterable {
    case pastor       = "Pastor"
    case teacher      = "Teacher"
    case worship      = "Worship"
    case apologetics  = "Apologetics"
    case devotional   = "Devotional"
    case podcast      = "Podcast"
    case youth        = "Youth"
    case missionary   = "Missionary"

    var icon: String {
        switch self {
        case .pastor:      return "person.badge.shield.checkmark.fill"
        case .teacher:     return "graduationcap.fill"
        case .worship:     return "music.note"
        case .apologetics: return "text.magnifyingglass"
        case .devotional:  return "book.closed.fill"
        case .podcast:     return "mic.fill"
        case .youth:       return "figure.run"
        case .missionary:  return "globe.americas.fill"
        }
    }

    var color: Color {
        switch self {
        case .pastor:      return Color(red: 0.42, green: 0.24, blue: 0.82)
        case .teacher:     return Color(red: 0.20, green: 0.52, blue: 0.85)
        case .worship:     return Color(red: 0.85, green: 0.28, blue: 0.55)
        case .apologetics: return Color(red: 0.15, green: 0.55, blue: 0.42)
        case .devotional:  return Color(red: 0.90, green: 0.47, blue: 0.10)
        case .podcast:     return Color(red: 0.55, green: 0.28, blue: 0.85)
        case .youth:       return Color(red: 0.18, green: 0.70, blue: 0.45)
        case .missionary:  return Color(red: 0.75, green: 0.32, blue: 0.20)
        }
    }
}

struct ContentSeries: Identifiable, Codable {
    var id: String = UUID().uuidString
    var creatorID: String
    var title: String
    var description: String
    var episodeCount: Int
    var category: CreatorCategory
    var coverImageURL: String
    var isSubscriberOnly: Bool
    var likeCount: Int
    var saveCount: Int
    var publishedAt: Date
}

struct CreatorPost: Identifiable, Codable {
    var id: String = UUID().uuidString
    var creatorID: String
    var title: String
    var excerpt: String
    var scripture: String
    var type: ContentType
    var durationMinutes: Int
    var isSubscriberOnly: Bool
    var likeCount: Int
    var publishedAt: Date

    enum ContentType: String, Codable {
        case devotional = "Devotional"
        case teaching   = "Teaching"
        case podcast    = "Podcast"
        case video      = "Video"
        case reflection = "Reflection"
    }
}

// MARK: - Store

@MainActor
final class CreatorStore: ObservableObject {
    static let shared = CreatorStore()

    @Published var featuredCreators: [FaithCreator] = []
    @Published var allCreators: [FaithCreator] = []
    @Published var trendingSeries: [ContentSeries] = []
    @Published var recentPosts: [CreatorPost] = []
    @Published var followedCreatorIDs: Set<String> = []
    @Published var isLoading = false

    private let db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []

    private init() {}

    func loadAll() {
        guard !isLoading else { return }
        isLoading = true

        let creatorsListener = db.collection("faithCreators")
            .order(by: "subscriberCount", descending: true)
            .limit(to: 30)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self, let snap else { return }
                self.isLoading = false
                let loaded = snap.documents.compactMap { try? $0.data(as: FaithCreator.self) }
                if loaded.isEmpty {
                    self.allCreators = CreatorStore.demoCreators
                    self.featuredCreators = Array(CreatorStore.demoCreators.prefix(3))
                } else {
                    self.allCreators = loaded
                    self.featuredCreators = Array(loaded.prefix(3))
                }
            }
        listeners.append(creatorsListener)

        let seriesListener = db.collection("contentSeries")
            .order(by: "likeCount", descending: true)
            .limit(to: 12)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self, let snap else { return }
                let loaded = snap.documents.compactMap { try? $0.data(as: ContentSeries.self) }
                self.trendingSeries = loaded.isEmpty ? CreatorStore.demoSeries : loaded
            }
        listeners.append(seriesListener)

        let postsListener = db.collection("creatorPosts")
            .order(by: "publishedAt", descending: true)
            .limit(to: 20)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self, let snap else { return }
                let loaded = snap.documents.compactMap { try? $0.data(as: CreatorPost.self) }
                self.recentPosts = loaded.isEmpty ? CreatorStore.demoPosts : loaded
            }
        listeners.append(postsListener)

        // Followed creators
        if let uid = Auth.auth().currentUser?.uid {
            let followListener = db.collection("creatorFollows")
                .whereField("followerUID", isEqualTo: uid)
                .addSnapshotListener { [weak self] snap, _ in
                    guard let self, let snap else { return }
                    self.followedCreatorIDs = Set(snap.documents.compactMap { $0.data()["creatorID"] as? String })
                }
            listeners.append(followListener)
        }
    }

    func followCreator(_ creatorID: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let docID = "\(uid)_\(creatorID)"
        try await db.collection("creatorFollows").document(docID).setData([
            "followerUID": uid,
            "creatorID": creatorID,
            "followedAt": Timestamp(date: Date())
        ])
        followedCreatorIDs.insert(creatorID)
    }

    func unfollowCreator(_ creatorID: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let docID = "\(uid)_\(creatorID)"
        try await db.collection("creatorFollows").document(docID).delete()
        followedCreatorIDs.remove(creatorID)
    }

    func sendTip(to creatorID: String, amount: Double, message: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await db.collection("creatorTips").addDocument(data: [
            "fromUID": uid,
            "creatorID": creatorID,
            "amount": amount,
            "message": message,
            "sentAt": Timestamp(date: Date())
        ])
    }

    func stopListening() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
    }

    // MARK: - Demo Data

    static let demoCreators: [FaithCreator] = [
        FaithCreator(
            displayName: "Pastor David Osei",
            handle: "pastordavidosei",
            bio: "Senior Pastor at Grace Chapel | Biblical expositor | Author of 'Walking in His Truth' | Helping believers dig deep into Scripture.",
            avatarURL: "",
            bannerColor: "#3A1A6E",
            category: .pastor,
            specialties: ["Expository Preaching", "Discipleship", "Church Leadership"],
            subscriberCount: 12400,
            isVerified: true,
            tipJarEnabled: true,
            subscriptionPrice: 0,
            totalContent: 148,
            featuredSeries: "Romans: The Power of the Gospel",
            socialLinks: [:],
            createdAt: Date().addingTimeInterval(-86400 * 365)
        ),
        FaithCreator(
            displayName: "Priya Anand",
            handle: "priyateaches",
            bio: "Biblical scholar & apologist. Former skeptic turned believer. Helping you think clearly about your faith and answer hard questions.",
            avatarURL: "",
            bannerColor: "#155535",
            category: .apologetics,
            specialties: ["Christian Apologetics", "Philosophy", "Evidence for Faith"],
            subscriberCount: 8750,
            isVerified: true,
            tipJarEnabled: true,
            subscriptionPrice: 4.99,
            totalContent: 92,
            featuredSeries: "Answering the Hard Questions",
            socialLinks: [:],
            createdAt: Date().addingTimeInterval(-86400 * 500)
        ),
        FaithCreator(
            displayName: "Marcus Thompson",
            handle: "marcusworship",
            bio: "Worship leader, songwriter, and speaker. Creating devotional content that meets you right where you are.",
            avatarURL: "",
            bannerColor: "#8B2352",
            category: .worship,
            specialties: ["Worship", "Songwriting", "Daily Devotionals"],
            subscriberCount: 22100,
            isVerified: true,
            tipJarEnabled: true,
            subscriptionPrice: 0,
            totalContent: 214,
            featuredSeries: "30-Day Worship Devotional",
            socialLinks: [:],
            createdAt: Date().addingTimeInterval(-86400 * 730)
        ),
        FaithCreator(
            displayName: "Dr. Hannah Chen",
            handle: "hannahteachesyouth",
            bio: "Youth pastor & educator. Making theology accessible for the next generation. Resources for youth workers and parents.",
            avatarURL: "",
            bannerColor: "#14783E",
            category: .youth,
            specialties: ["Youth Ministry", "Teen Discipleship", "Family Faith"],
            subscriberCount: 5300,
            isVerified: false,
            tipJarEnabled: true,
            subscriptionPrice: 0,
            totalContent: 67,
            featuredSeries: "Who Am I in Christ? (For Teens)",
            socialLinks: [:],
            createdAt: Date().addingTimeInterval(-86400 * 200)
        ),
        FaithCreator(
            displayName: "Brother Samuel Okonkwo",
            handle: "brothersamuel",
            bio: "Missionary in West Africa. Real stories of faith, miracles, and what it means to follow Jesus on the frontlines.",
            avatarURL: "",
            bannerColor: "#7B2E0E",
            category: .missionary,
            specialties: ["Missions", "Church Planting", "Evangelism"],
            subscriberCount: 3900,
            isVerified: true,
            tipJarEnabled: true,
            subscriptionPrice: 0,
            totalContent: 43,
            featuredSeries: "Field Notes from Nigeria",
            socialLinks: [:],
            createdAt: Date().addingTimeInterval(-86400 * 400)
        ),
    ]

    static let demoSeries: [ContentSeries] = [
        ContentSeries(creatorID: "1", title: "Romans: The Power of the Gospel", description: "A verse-by-verse study through the most theologically rich letter in the New Testament.", episodeCount: 28, category: .pastor, coverImageURL: "", isSubscriberOnly: false, likeCount: 4200, saveCount: 1800, publishedAt: Date().addingTimeInterval(-86400 * 14)),
        ContentSeries(creatorID: "3", title: "30-Day Worship Devotional", description: "A daily devotional journey pairing scripture with reflection, designed to draw your heart into worship.", episodeCount: 30, category: .worship, coverImageURL: "", isSubscriberOnly: false, likeCount: 8100, saveCount: 3400, publishedAt: Date().addingTimeInterval(-86400 * 7)),
        ContentSeries(creatorID: "2", title: "Answering the Hard Questions", description: "Can you trust the Bible? Did Jesus really rise? This series tackles the toughest objections to Christianity.", episodeCount: 12, category: .apologetics, coverImageURL: "", isSubscriberOnly: true, likeCount: 2900, saveCount: 1100, publishedAt: Date().addingTimeInterval(-86400 * 21)),
        ContentSeries(creatorID: "4", title: "Who Am I in Christ? (For Teens)", description: "Identity, purpose, and belonging — what does the Bible say about who you are?", episodeCount: 8, category: .youth, coverImageURL: "", isSubscriberOnly: false, likeCount: 1500, saveCount: 700, publishedAt: Date().addingTimeInterval(-86400 * 5)),
    ]

    static let demoPosts: [CreatorPost] = [
        CreatorPost(creatorID: "3", title: "When You Don't Feel Like Worshipping", excerpt: "Feelings can be deceptive guides in faith. Learn why worship is an act of will, not emotion — and how to choose it even in the valley.", scripture: "Psalm 42:5", type: .devotional, durationMinutes: 5, isSubscriberOnly: false, likeCount: 312, publishedAt: Date().addingTimeInterval(-86400 * 1)),
        CreatorPost(creatorID: "1", title: "Romans 8:28 — What It Really Means", excerpt: "\"All things work together for good\" — this verse is often misapplied. What did Paul actually mean, and how does it change how we pray?", scripture: "Romans 8:28", type: .teaching, durationMinutes: 22, isSubscriberOnly: false, likeCount: 894, publishedAt: Date().addingTimeInterval(-86400 * 3)),
        CreatorPost(creatorID: "2", title: "Did Jesus Actually Rise from the Dead?", excerpt: "The historical evidence for the resurrection is more compelling than most people realize. Let's look at the facts.", scripture: "1 Corinthians 15:3-8", type: .teaching, durationMinutes: 35, isSubscriberOnly: true, likeCount: 1240, publishedAt: Date().addingTimeInterval(-86400 * 5)),
        CreatorPost(creatorID: "5", title: "Field Notes: A Church Planted in Kano", excerpt: "Three years ago I arrived with nothing but a Bible and a calling. This is the story of what God built.", scripture: "Acts 2:47", type: .reflection, durationMinutes: 8, isSubscriberOnly: false, likeCount: 456, publishedAt: Date().addingTimeInterval(-86400 * 7)),
        CreatorPost(creatorID: "4", title: "Why Your Teen Feels Invisible at Church", excerpt: "Youth aren't the church of tomorrow — they're the church of today. Practical steps for leaders and parents.", scripture: "1 Timothy 4:12", type: .teaching, durationMinutes: 14, isSubscriberOnly: false, likeCount: 278, publishedAt: Date().addingTimeInterval(-86400 * 10)),
    ]
}

// MARK: - Main View

struct CreatorView: View {
    @StateObject private var store = CreatorStore.shared
    @State private var selectedTab: CreatorTab = .discover
    @State private var selectedCategory: CreatorCategory? = nil
    @State private var searchText = ""
    @State private var appeared = false
    @State private var selectedCreator: FaithCreator?
    @State private var showTipSheet = false
    @State private var tipTarget: FaithCreator?

    enum CreatorTab: String, CaseIterable {
        case discover  = "Discover"
        case series    = "Series"
        case following = "Following"
    }

    var filteredCreators: [FaithCreator] {
        var list = store.allCreators
        if let cat = selectedCategory { list = list.filter { $0.category == cat } }
        if !searchText.isEmpty {
            list = list.filter {
                $0.displayName.localizedCaseInsensitiveContains(searchText) ||
                $0.bio.localizedCaseInsensitiveContains(searchText) ||
                $0.specialties.joined().localizedCaseInsensitiveContains(searchText)
            }
        }
        return list
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    heroHeader
                    tabPills.padding(.vertical, 8)
                    tabContent.padding(.bottom, 32)
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                store.loadAll()
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
                    appeared = true
                }
            }
            .onDisappear { store.stopListening() }
            .sheet(item: $selectedCreator) { creator in
                CreatorProfileSheet(creator: creator, store: store)
            }
            .sheet(item: $tipTarget) { creator in
                TipJarSheet(creator: creator, store: store)
            }
        }
    }

    // MARK: - Hero

    private var heroHeader: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [
                    Color(red: 0.58, green: 0.15, blue: 0.75),
                    Color(red: 0.85, green: 0.28, blue: 0.55),
                    Color(red: 0.95, green: 0.55, blue: 0.22),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 200)
            .overlay(
                ZStack {
                    Circle().fill(Color.white.opacity(0.05)).frame(width: 180).offset(x: 80, y: -30)
                    Circle().fill(Color.white.opacity(0.04)).frame(width: 120).offset(x: -90, y: 20)
                }
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Creator Hub")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                        Text("Faith teachers, podcasters & worship leaders")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    Spacer()
                    // Total creators badge
                    VStack(spacing: 2) {
                        Text("\(store.allCreators.count)")
                            .font(.system(size: 20, weight: .black))
                            .foregroundStyle(.white)
                        Text("Creators")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.25), lineWidth: 1))
                }
                .padding(.horizontal, 20)
                .padding(.top, 56)
                .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Tab Pills

    private var tabPills: some View {
        HStack(spacing: 8) {
            ForEach(CreatorTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 14, weight: selectedTab == tab ? .semibold : .regular))
                        .foregroundStyle(selectedTab == tab ? .white : .primary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(
                            Group {
                                if selectedTab == tab {
                                    Capsule().fill(Color(red: 0.58, green: 0.15, blue: 0.75))
                                } else {
                                    Capsule().fill(Color(.secondarySystemBackground))
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .discover:  discoverTab
        case .series:    seriesTab
        case .following: followingTab
        }
    }

    // MARK: - Discover Tab

    private var discoverTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Search
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search creators...", text: $searchText)
                    .font(.system(size: 15))
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)

            // Category filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryPill(nil, label: "All")
                    ForEach(CreatorCategory.allCases, id: \.self) { cat in
                        categoryPill(cat, label: cat.rawValue)
                    }
                }
                .padding(.horizontal, 20)
            }

            // Featured creators horizontal scroll
            if searchText.isEmpty && selectedCategory == nil {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Featured")
                        .font(.system(size: 18, weight: .bold))
                        .padding(.horizontal, 20)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(Array(store.featuredCreators.enumerated()), id: \.element.id) { idx, creator in
                                FeaturedCreatorCard(
                                    creator: creator,
                                    isFollowed: store.followedCreatorIDs.contains(creator.id)
                                )
                                .frame(width: 200)
                                .onTapGesture { selectedCreator = creator }
                                .opacity(appeared ? 1 : 0)
                                .offset(x: appeared ? 0 : 30)
                                .animation(.spring(response: 0.5, dampingFraction: 0.75).delay(Double(idx) * 0.08), value: appeared)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }

            // All / filtered list
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(searchText.isEmpty && selectedCategory == nil ? "All Creators" : "Results")
                        .font(.system(size: 18, weight: .bold))
                    Spacer()
                    Text("\(filteredCreators.count)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(.tertiarySystemBackground), in: Capsule())
                }
                .padding(.horizontal, 20)

                LazyVStack(spacing: 12) {
                    ForEach(Array(filteredCreators.enumerated()), id: \.element.id) { idx, creator in
                        CreatorListCard(
                            creator: creator,
                            isFollowed: store.followedCreatorIDs.contains(creator.id),
                            onFollow: {
                                Task {
                                    if store.followedCreatorIDs.contains(creator.id) {
                                        try? await store.unfollowCreator(creator.id)
                                    } else {
                                        try? await store.followCreator(creator.id)
                                    }
                                }
                            },
                            onTip: {
                                tipTarget = creator
                            }
                        )
                        .padding(.horizontal, 20)
                        .onTapGesture { selectedCreator = creator }
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 16)
                        .animation(.spring(response: 0.4, dampingFraction: 0.75).delay(0.05 + Double(idx) * 0.04), value: appeared)
                    }
                }
            }
        }
    }

    private func categoryPill(_ cat: CreatorCategory?, label: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                selectedCategory = cat
            }
        } label: {
            HStack(spacing: 5) {
                if let cat {
                    Image(systemName: cat.icon).font(.system(size: 11))
                }
                Text(label).font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(selectedCategory == cat ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Group {
                    if selectedCategory == cat {
                        Capsule().fill(cat?.color ?? Color(red: 0.58, green: 0.15, blue: 0.75))
                    } else {
                        Capsule().fill(Color(.secondarySystemBackground))
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Series Tab

    private var seriesTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Teaching Series")
                .font(.system(size: 20, weight: .bold))
                .padding(.horizontal, 20)
                .padding(.top, 4)

            // Latest posts
            VStack(alignment: .leading, spacing: 12) {
                Text("Recent Content")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)

                LazyVStack(spacing: 10) {
                    ForEach(Array(store.recentPosts.enumerated()), id: \.element.id) { idx, post in
                        ContentPostCard(post: post, creator: creatorFor(post.creatorID))
                            .padding(.horizontal, 20)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 12)
                            .animation(.spring(response: 0.4, dampingFraction: 0.75).delay(Double(idx) * 0.05), value: appeared)
                    }
                }
            }

            // Series grid
            VStack(alignment: .leading, spacing: 12) {
                Text("Series")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(Array(store.trendingSeries.enumerated()), id: \.element.id) { idx, series in
                        SeriesCard(series: series, creator: creatorFor(series.creatorID))
                            .opacity(appeared ? 1 : 0)
                            .scaleEffect(appeared ? 1 : 0.92)
                            .animation(.spring(response: 0.45, dampingFraction: 0.75).delay(Double(idx) * 0.06), value: appeared)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Following Tab

    private var followingTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Following")
                .font(.system(size: 20, weight: .bold))
                .padding(.horizontal, 20)
                .padding(.top, 4)

            let followed = store.allCreators.filter { store.followedCreatorIDs.contains($0.id) }

            if followed.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 44))
                        .foregroundStyle(Color(red: 0.58, green: 0.15, blue: 0.75).opacity(0.5))
                    Text("You're not following anyone yet")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Discover faith creators and follow them to see their content here.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button {
                        withAnimation { selectedTab = .discover }
                    } label: {
                        Text("Browse Creators")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color(red: 0.58, green: 0.15, blue: 0.75), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(32)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(followed) { creator in
                        CreatorListCard(
                            creator: creator,
                            isFollowed: true,
                            onFollow: {
                                Task { try? await store.unfollowCreator(creator.id) }
                            },
                            onTip: { tipTarget = creator }
                        )
                        .padding(.horizontal, 20)
                        .onTapGesture { selectedCreator = creator }
                    }
                }
            }
        }
    }

    private func creatorFor(_ id: String) -> FaithCreator? {
        store.allCreators.first { $0.id == id }
    }
}

// MARK: - Featured Creator Card

struct FeaturedCreatorCard: View {
    let creator: FaithCreator
    let isFollowed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Avatar + verified
            ZStack(alignment: .bottomTrailing) {
                LinearGradient(
                    colors: [creator.category.color, creator.category.color.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: 52, height: 52)
                .clipShape(Circle())
                .overlay(
                    Text(String(creator.displayName.prefix(1)))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                )

                if creator.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(red: 0.28, green: 0.52, blue: 0.90))
                        .background(Color.white, in: Circle())
                        .offset(x: 2, y: 2)
                }
            }

            Text(creator.displayName)
                .font(.system(size: 15, weight: .bold))
                .lineLimit(1)

            Text(creator.category.rawValue)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(creator.category.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(creator.category.color.opacity(0.12), in: Capsule())

            Text(creator.bio)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("\(formatCount(creator.subscriberCount)) followers")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(creator.category.color.opacity(0.2), lineWidth: 1)
        )
    }

    private func formatCount(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n) / 1000.0) : "\(n)"
    }
}

// MARK: - Creator List Card

struct CreatorListCard: View {
    let creator: FaithCreator
    let isFollowed: Bool
    let onFollow: () -> Void
    let onTip: () -> Void
    @State private var followLoading = false

    var body: some View {
        HStack(spacing: 14) {
            // Avatar
            ZStack(alignment: .bottomTrailing) {
                LinearGradient(
                    colors: [creator.category.color, creator.category.color.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: 50, height: 50)
                .clipShape(Circle())
                .overlay(
                    Text(String(creator.displayName.prefix(1)))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                )

                if creator.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(red: 0.28, green: 0.52, blue: 0.90))
                        .background(Color.white, in: Circle())
                        .offset(x: 2, y: 2)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(creator.displayName)
                        .font(.system(size: 15, weight: .semibold))
                    Text(creator.category.rawValue)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(creator.category.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(creator.category.color.opacity(0.1), in: Capsule())
                }
                Text(creator.bio)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("\(formatCount(creator.subscriberCount)) followers · \(creator.totalContent) posts")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(spacing: 8) {
                Button {
                    followLoading = true
                    onFollow()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { followLoading = false }
                } label: {
                    if followLoading {
                        ProgressView().scaleEffect(0.7).frame(width: 60)
                    } else {
                        Text(isFollowed ? "Following" : "Follow")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isFollowed ? Color(red: 0.58, green: 0.15, blue: 0.75) : .white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Group {
                                    if isFollowed {
                                        Capsule().stroke(Color(red: 0.58, green: 0.15, blue: 0.75), lineWidth: 1.5)
                                    } else {
                                        Capsule().fill(Color(red: 0.58, green: 0.15, blue: 0.75))
                                    }
                                }
                            )
                    }
                }
                .buttonStyle(.plain)

                if creator.tipJarEnabled {
                    Button {
                        onTip()
                    } label: {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(red: 0.90, green: 0.47, blue: 0.10))
                    }
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func formatCount(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n) / 1000.0) : "\(n)"
    }
}

// MARK: - Content Post Card

struct ContentPostCard: View {
    let post: CreatorPost
    let creator: FaithCreator?

    var body: some View {
        HStack(spacing: 12) {
            // Type icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(typeColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: typeIcon)
                    .font(.system(size: 18))
                    .foregroundStyle(typeColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(post.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    if post.isSubscriberOnly {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(post.excerpt)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 10) {
                    if let creator {
                        Text(creator.displayName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(creator.category.color)
                    }
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text("\(post.durationMinutes) min")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if !post.scripture.isEmpty {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(post.scripture)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(red: 0.42, green: 0.24, blue: 0.82))
                    }
                }
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "heart")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("\(post.likeCount)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var typeIcon: String {
        switch post.type {
        case .devotional: return "book.closed.fill"
        case .teaching:   return "graduationcap.fill"
        case .podcast:    return "mic.fill"
        case .video:      return "play.circle.fill"
        case .reflection: return "pencil.and.scribble"
        }
    }

    private var typeColor: Color {
        switch post.type {
        case .devotional: return Color(red: 0.90, green: 0.47, blue: 0.10)
        case .teaching:   return Color(red: 0.20, green: 0.52, blue: 0.85)
        case .podcast:    return Color(red: 0.55, green: 0.28, blue: 0.85)
        case .video:      return Color(red: 0.85, green: 0.20, blue: 0.35)
        case .reflection: return Color(red: 0.42, green: 0.24, blue: 0.82)
        }
    }
}

// MARK: - Series Card

struct SeriesCard: View {
    let series: ContentSeries
    let creator: FaithCreator?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Cover
            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    colors: [series.category.color, series.category.color.opacity(0.5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    Image(systemName: series.category.icon)
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.3))
                )

                if series.isSubscriberOnly {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(.black.opacity(0.4), in: Circle())
                        .padding(6)
                }
            }

            Text(series.title)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let creator {
                Text(creator.displayName)
                    .font(.system(size: 11))
                    .foregroundStyle(series.category.color)
            }

            HStack(spacing: 8) {
                Label("\(series.episodeCount) episodes", systemImage: "play.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(series.category.color.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Creator Profile Sheet

struct CreatorProfileSheet: View {
    let creator: FaithCreator
    @ObservedObject var store: CreatorStore
    @Environment(\.dismiss) private var dismiss
    @State private var showTipSheet = false
    @State private var isFollowing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Banner
                    LinearGradient(
                        colors: [creator.category.color, creator.category.color.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(height: 120)
                    .overlay(
                        Image(systemName: creator.category.icon)
                            .font(.system(size: 50))
                            .foregroundStyle(.white.opacity(0.15))
                    )

                    // Avatar + info
                    VStack(spacing: 12) {
                        ZStack(alignment: .bottomTrailing) {
                            LinearGradient(
                                colors: [creator.category.color, creator.category.color.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .frame(width: 72, height: 72)
                            .clipShape(Circle())
                            .overlay(
                                Text(String(creator.displayName.prefix(1)))
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(.white)
                            )
                            .overlay(Circle().stroke(.white, lineWidth: 3))
                            .offset(y: -36)

                            if creator.isVerified {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Color(red: 0.28, green: 0.52, blue: 0.90))
                                    .background(Color.white, in: Circle())
                                    .offset(x: 4, y: -32)
                            }
                        }

                        Text(creator.displayName)
                            .font(.system(size: 20, weight: .bold))
                            .offset(y: -28)
                        Text("@\(creator.handle)")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .offset(y: -28)
                        Text(creator.category.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(creator.category.color)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(creator.category.color.opacity(0.12), in: Capsule())
                            .offset(y: -28)
                    }
                    .padding(.horizontal, 20)

                    // Stats row
                    HStack(spacing: 0) {
                        statBlock("\(formatCount(creator.subscriberCount))", label: "Followers")
                        Divider().frame(height: 40)
                        statBlock("\(creator.totalContent)", label: "Posts")
                        Divider().frame(height: 40)
                        statBlock(creator.subscriptionPrice > 0 ? "$\(String(format: "%.2f", creator.subscriptionPrice))/mo" : "Free", label: "Access")
                    }
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground))
                    .padding(.horizontal, 20)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 20)
                    .offset(y: -16)

                    VStack(alignment: .leading, spacing: 20) {
                        // Bio
                        Text(creator.bio)
                            .font(.system(size: 15))
                            .lineSpacing(4)

                        // Specialties
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Specialties")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(creator.specialties, id: \.self) { s in
                                        Text(s)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(creator.category.color)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(creator.category.color.opacity(0.1), in: Capsule())
                                    }
                                }
                            }
                        }

                        // Featured series
                        if !creator.featuredSeries.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Featured Series")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(creator.category.color.opacity(0.12))
                                            .frame(width: 44, height: 44)
                                        Image(systemName: "play.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundStyle(creator.category.color)
                                    }
                                    Text(creator.featuredSeries)
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .padding(12)
                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                            }
                        }

                        // Action buttons
                        HStack(spacing: 12) {
                            Button {
                                Task {
                                    if store.followedCreatorIDs.contains(creator.id) {
                                        try? await store.unfollowCreator(creator.id)
                                    } else {
                                        try? await store.followCreator(creator.id)
                                    }
                                }
                            } label: {
                                let followed = store.followedCreatorIDs.contains(creator.id)
                                Text(followed ? "Following" : "Follow")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(followed ? Color(red: 0.58, green: 0.15, blue: 0.75) : .white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        Group {
                                            if followed {
                                                RoundedRectangle(cornerRadius: 14)
                                                    .stroke(Color(red: 0.58, green: 0.15, blue: 0.75), lineWidth: 1.5)
                                            } else {
                                                RoundedRectangle(cornerRadius: 14)
                                                    .fill(Color(red: 0.58, green: 0.15, blue: 0.75))
                                            }
                                        }
                                    )
                            }
                            .buttonStyle(.plain)

                            if creator.tipJarEnabled {
                                Button {
                                    showTipSheet = true
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "gift.fill")
                                        Text("Tip")
                                    }
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.90, green: 0.47, blue: 0.10))
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 14)
                                    .background(Color(red: 1.0, green: 0.94, blue: 0.87), in: RoundedRectangle(cornerRadius: 14))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showTipSheet) {
                TipJarSheet(creator: creator, store: store)
            }
        }
    }

    private func statBlock(_ value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 16, weight: .bold))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private func formatCount(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n) / 1000.0) : "\(n)"
    }
}

// MARK: - Tip Jar Sheet

struct TipJarSheet: View {
    let creator: FaithCreator
    @ObservedObject var store: CreatorStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedAmount: Double = 5.0
    @State private var message: String = ""
    @State private var isSending = false
    @State private var didSend = false

    let amounts: [Double] = [1, 3, 5, 10, 25]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Creator header
                VStack(spacing: 8) {
                    ZStack {
                        LinearGradient(
                            colors: [creator.category.color, creator.category.color.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                        Text(String(creator.displayName.prefix(1)))
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    Text("Support \(creator.displayName)")
                        .font(.system(size: 18, weight: .bold))
                    Text("Your gift helps them keep creating faith content.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 8)

                // Amount picker
                VStack(alignment: .leading, spacing: 10) {
                    Text("Choose Amount")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        ForEach(amounts, id: \.self) { amt in
                            Button {
                                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                                    selectedAmount = amt
                                }
                            } label: {
                                Text("$\(Int(amt))")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(selectedAmount == amt ? .white : .primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        Group {
                                            if selectedAmount == amt {
                                                RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.90, green: 0.47, blue: 0.10))
                                            } else {
                                                RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground))
                                            }
                                        }
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)

                // Message
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add a Message (optional)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("Thank you for your ministry...", text: $message, axis: .vertical)
                        .font(.system(size: 14))
                        .lineLimit(3...4)
                        .padding(12)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 20)

                Spacer()

                // Send button
                Button {
                    sendTip()
                } label: {
                    Group {
                        if didSend {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Thank You Sent!")
                            }
                        } else if isSending {
                            ProgressView().tint(.white)
                        } else {
                            Text("Send $\(Int(selectedAmount)) Gift")
                        }
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        didSend ? Color.green : Color(red: 0.90, green: 0.47, blue: 0.10),
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                }
                .disabled(isSending || didSend)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: didSend)
            }
            .navigationTitle("Tip Jar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func sendTip() {
        isSending = true
        Task {
            try? await store.sendTip(to: creator.id, amount: selectedAmount, message: message)
            await MainActor.run {
                isSending = false
                didSend = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Entry Card for ResourcesView

struct CreatorHubEntryCard: View {
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.58, green: 0.15, blue: 0.75), Color(red: 0.85, green: 0.28, blue: 0.55)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                Image(systemName: "person.wave.2.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Creator Hub")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.primary)
                Text("Faith teachers · Devotionals · Podcasts · Tip jar")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color(red: 0.58, green: 0.15, blue: 0.75).opacity(0.15), lineWidth: 1)
                )
        )
        .scaleEffect(appeared ? 1 : 0.95)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.15)) {
                appeared = true
            }
        }
    }
}
