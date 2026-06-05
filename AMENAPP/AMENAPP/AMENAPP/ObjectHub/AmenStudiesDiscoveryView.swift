import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Studies Discovery Models

struct StudyItem: Identifiable, Codable {
    @DocumentID var id: String?
    let title: String
    let authorName: String?
    let authorAvatarURL: String?
    let coverImageURL: String?
    let scripture: String?
    let noteCount: Int
    let weeklyEngagement: Int
    let tags: [String]
    let createdAt: Timestamp?
    let sourceType: SourceType

    enum SourceType: String, Codable {
        case mentor    = "mentor"
        case church    = "church"
        case friend    = "friend"
        case personal  = "personal"
        case trending  = "trending"
    }
}

// MARK: - Studies Discovery ViewModel

@MainActor
final class AmenStudiesDiscoveryViewModel: ObservableObject {
    @Published var trendingStudies: [StudyItem] = []
    @Published var fromMentors: [StudyItem] = []
    @Published var fromChurch: [StudyItem] = []
    @Published var continueReading: [StudyItem] = []
    @Published var newThisWeek: [StudyItem] = []
    @Published var isLoading = false
    @Published var error: String?

    private let db = Firestore.firestore()

    func load() async {
        isLoading = true
        defer { isLoading = false }

        async let trendingTask  = fetchStudies(filter: .trending,  limit: 10)
        async let mentorsTask   = fetchStudies(filter: .mentor,    limit: 8)
        async let churchTask    = fetchStudies(filter: .church,    limit: 8)
        async let continueTask  = fetchContinueReading()
        async let newTask       = fetchNewThisWeek()

        let (t, m, c, cont, n) = await (trendingTask, mentorsTask, churchTask, continueTask, newTask)
        trendingStudies  = t
        fromMentors      = m
        fromChurch       = c
        continueReading  = cont
        newThisWeek      = n
    }

    private func fetchStudies(filter: StudyItem.SourceType, limit: Int) async -> [StudyItem] {
        let snap = try? await db.collection("churchNotes")
            .whereField("sourceType", isEqualTo: filter.rawValue)
            .whereField("isPublic", isEqualTo: true)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()

        return snap?.documents.compactMap { try? $0.data(as: StudyItem.self) } ?? []
    }

    private func fetchContinueReading() async -> [StudyItem] {
        guard let uid = Auth.auth().currentUser?.uid else { return [] }
        let snap = try? await db.collection("studyProgress")
            .whereField("userId", isEqualTo: uid)
            .whereField("completed", isEqualTo: false)
            .order(by: "lastReadAt", descending: true)
            .limit(to: 6)
            .getDocuments()

        guard let snap else { return [] }
        let studyIds = snap.documents.compactMap { $0.data()["studyId"] as? String }

        var items: [StudyItem] = []
        for sid in studyIds.prefix(6) {
            if let doc = try? await db.collection("churchNotes").document(sid).getDocument(),
               let item = try? doc.data(as: StudyItem.self) {
                items.append(item)
            }
        }
        return items
    }

    private func fetchNewThisWeek() async -> [StudyItem] {
        let oneWeekAgo = Date().addingTimeInterval(-7 * 86400)
        let snap = try? await db.collection("churchNotes")
            .whereField("isPublic", isEqualTo: true)
            .whereField("createdAt", isGreaterThan: Timestamp(date: oneWeekAgo))
            .order(by: "createdAt", descending: true)
            .limit(to: 10)
            .getDocuments()

        return snap?.documents.compactMap { try? $0.data(as: StudyItem.self) } ?? []
    }
}

// MARK: - Studies Discovery View

/// A8: Notes/Studies discovery surface — the "Albums → Studies" analogy.
/// Rails: Trending Studies · From Mentors · From Your Church ·
///        Continue Reading · New This Week.
/// Each study card links to the community around that content.
struct AmenStudiesDiscoveryView: View {
    @StateObject private var vm = AmenStudiesDiscoveryViewModel()
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedStudy: StudyItem?
    @State private var showDiscussionRoom = false
    @State private var selectedStudyForRoom: StudyItem?

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    loadingState
                } else {
                    contentList
                }
            }
            .navigationTitle("Studies & Notes")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // Search
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Search studies")
                }
            }
        }
        .task { await vm.load() }
        .sheet(isPresented: $showDiscussionRoom) {
            if let study = selectedStudyForRoom {
                AmenObjectDiscussionRoomView(
                    objectId:     "study-\(study.id ?? UUID().uuidString)",
                    objectTitle:  study.title,
                    roomType:     .studyGroup,
                    existingRoom: nil
                )
            }
        }
    }

    // MARK: - Content

    private var contentList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                // Continue Reading (pinned at top if present)
                if !vm.continueReading.isEmpty {
                    studiesRail(
                        title: "Continue Reading",
                        subtitle: "Pick up where you left off",
                        icon: "bookmark.fill",
                        color: .purple,
                        items: vm.continueReading,
                        cardStyle: .compact
                    )
                    Divider().padding(.horizontal, 20)
                }

                // Featured Studies
                if !vm.trendingStudies.isEmpty {
                    studiesRail(
                        title: "Featured Studies",
                        subtitle: "Recently added",
                        icon: "star.fill",
                        color: .orange,
                        items: vm.trendingStudies,
                        cardStyle: .featured
                    )
                    Divider().padding(.horizontal, 20)
                }

                // From Mentors
                if !vm.fromMentors.isEmpty {
                    studiesRail(
                        title: "Notes from Mentors",
                        subtitle: "Teachings you follow",
                        icon: "person.2.fill",
                        color: .blue,
                        items: vm.fromMentors,
                        cardStyle: .compact
                    )
                    Divider().padding(.horizontal, 20)
                }

                // From Your Church
                if !vm.fromChurch.isEmpty {
                    studiesRail(
                        title: "From Your Church",
                        subtitle: "Shared by your community",
                        icon: "building.columns.fill",
                        color: .teal,
                        items: vm.fromChurch,
                        cardStyle: .compact
                    )
                    Divider().padding(.horizontal, 20)
                }

                // New This Week
                if !vm.newThisWeek.isEmpty {
                    studiesRail(
                        title: "New This Week",
                        subtitle: "Fresh notes and studies",
                        icon: "sparkles",
                        color: .yellow,
                        items: vm.newThisWeek,
                        cardStyle: .compact
                    )
                }

                if vm.trendingStudies.isEmpty && vm.fromMentors.isEmpty && vm.fromChurch.isEmpty {
                    emptyState
                }

                Spacer(minLength: 60)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - Rail

    private enum CardStyle { case featured, compact }

    private func studiesRail(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        items: [StudyItem],
        cardStyle: CardStyle
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Rail header
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(color.opacity(0.12)).frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("See all")
                    .font(.subheadline)
                    .foregroundStyle(.purple)
            }
            .padding(.horizontal, 20)

            // Cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { item in
                        if cardStyle == .featured {
                            FeaturedStudyCard(item: item) {
                                selectedStudyForRoom = item
                                showDiscussionRoom = true
                            }
                        } else {
                            CompactStudyCard(item: item) {
                                selectedStudyForRoom = item
                                showDiscussionRoom = true
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
            }
        }
        .padding(.vertical, 20)
    }

    // MARK: - Loading / Empty

    private var loadingState: some View {
        VStack(spacing: 28) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 12) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(height: 20)
                        .padding(.horizontal, 20)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(0..<4, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.secondary.opacity(0.08))
                                    .frame(width: 140, height: 160)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
        }
        .padding(.top, 20)
        .accessibilityLabel("Loading studies")
        .accessibilityHidden(true)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("No studies yet.")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Studies from mentors, your church, and the community will appear here.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.top, 60)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Featured Study Card (larger, for Trending)

private struct FeaturedStudyCard: View {
    let item: StudyItem
    let onDiscuss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Cover
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.25), Color.indigo.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 200, height: 130)

                if let coverURL = item.coverImageURL, let url = URL(string: coverURL) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                        }
                    }
                    .frame(width: 200, height: 130)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                // Discuss chip
                Button(action: onDiscuss) {
                    HStack(spacing: 4) {
                        Image(systemName: "book.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Study Group")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.purple.opacity(0.85)))
                }
                .buttonStyle(.plain)
                .padding(10)
            }
            .frame(width: 200, height: 130)

            // Title
            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(width: 200, alignment: .leading)

            // Author + scripture
            HStack(spacing: 6) {
                if let author = item.authorName {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let scripture = item.scripture {
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(scripture)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 200, alignment: .leading)

            // Notes count (non-comparative)
            HStack(spacing: 12) {
                Label("\(item.noteCount) notes", systemImage: "doc.text")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 200, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title)\(item.authorName.map { " by \($0)" } ?? ""). \(item.noteCount) notes.")
    }
}

// MARK: - Compact Study Card

private struct CompactStudyCard: View {
    let item: StudyItem
    let onDiscuss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.purple.opacity(0.08))
                    .frame(width: 140, height: 100)

                if let coverURL = item.coverImageURL, let url = URL(string: coverURL) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                        }
                    }
                    .frame(width: 140, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.purple.opacity(0.3))
                }
            }
            .frame(width: 140, height: 100)
            .onTapGesture(perform: onDiscuss)

            Text(item.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(width: 140, alignment: .leading)

            if let author = item.authorName {
                Text(author)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 140, alignment: .leading)
            }

            if let scripture = item.scripture {
                Text(scripture)
                    .font(.caption2.italic())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(width: 140, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title)\(item.authorName.map { " by \($0)" } ?? "")")
        .accessibilityHint("Double-tap to open study group")
    }
}
