import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Covenant Home View
// Command center for a user's paid community membership.
// Sections: Pinned Covenants, Continue, Today's Digest, Prayer Follow-ups,
// Creator Events, Mentioned Rooms, New Paid Posts, Suggested Creators, Sunday Mode.

struct AmenCovenantHomeView: View {
    @StateObject private var service = CovenantService.shared
    @StateObject private var vm = AmenCovenantHomeViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSearch = false
    @State private var showActivityCenter = false
    @State private var showComposer = false
    @State private var scrollOffset: CGFloat = 0
    @State private var showDigestSheet = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    offsetReader

                    LazyVStack(spacing: 0) {
                        // Hero Mode banner when operating mode is set
                        if let mode = vm.activeMode {
                            modeBanner(mode)
                                .padding(.horizontal, 20)
                                .padding(.top, 8)
                                .padding(.bottom, 4)
                        }

                        sectionHeader("Pinned Covenants")
                        pinnedCovenantsRail

                        if !vm.continueItems.isEmpty {
                            sectionHeader("Continue Where You Left Off")
                            continueRail
                        }

                        sectionHeader("Today's Digest")
                        digestCard

                        if !service.prayerRequests.isEmpty {
                            sectionHeader("Prayer Requests Needing Follow-Up")
                            prayerFollowUpRail
                        }

                        if !vm.upcomingEvents.isEmpty {
                            sectionHeader("Upcoming Creator Events")
                            eventsRail
                        }

                        if !vm.mentionedRooms.isEmpty {
                            sectionHeader("Rooms With Mentions")
                            mentionedRoomsRail
                        }

                        sectionHeader("New from Creators")
                        newPaidPostsRail

                        sectionHeader("Suggested Creators")
                        suggestedCreatorsRail

                        Spacer(minLength: 120)
                    }
                }
                .coordinateSpace(name: "scroll")
                .background(Color(uiColor: .systemGroupedBackground))

                floatingBar
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { navToolbar }
            .task {
                await service.loadMyCovenants()
                service.loadActivity()
                await vm.load()
            }
            .sheet(isPresented: $showSearch) {
                AmenCovenantSearchView()
            }
            .sheet(isPresented: $showActivityCenter) {
                AmenCovenantActivityCenterView()
            }
            .sheet(isPresented: $showDigestSheet) {
                CovenantDailyDigestSheet(
                    postCount: 4,
                    prayerUpdateCount: 2,
                    eventCount: 1
                )
            }
        }
    }

    // MARK: - Scroll offset reader (for reactive chrome)

    private var offsetReader: some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: ScrollOffsetKey.self,
                value: geo.frame(in: .named("scroll")).minY
            )
        }
        .frame(height: 0)
        .onPreferenceChange(ScrollOffsetKey.self) { scrollOffset = $0 }
    }

    // MARK: - Floating Bar

    private var floatingBar: some View {
        HStack(spacing: 16) {
            Button {
                showSearch = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.systemScaled(15, weight: .medium))
                    Text("Search communities…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                )
            }
            .buttonStyle(.plain)

            Button {
                showComposer = true
            } label: {
                Image(systemName: "plus.bubble.fill")
                    .font(.systemScaled(18))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.purple))
                    .shadow(color: .purple.opacity(0.3), radius: 8, y: 3)
            }
            .accessibilityLabel("New message")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    // MARK: - Nav Toolbar

    @ToolbarContentBuilder
    private var navToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text("Communities")
                .font(.headline)
                .opacity(scrollOffset < -40 ? 1 : 0)
                .animation(reduceMotion ? .none : .easeInOut(duration: 0.2), value: scrollOffset)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showActivityCenter = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell")
                        .font(.systemScaled(17))
                    if vm.unreadActivityCount > 0 {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .offset(x: 3, y: -3)
                    }
                }
            }
            .accessibilityLabel("Activity Center, \(vm.unreadActivityCount) unread")
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    // MARK: - Mode Banner

    private func modeBanner(_ mode: CovenantOperatingMode) -> some View {
        HStack(spacing: 12) {
            Image(systemName: mode.icon)
                .font(.systemScaled(16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.purple.opacity(0.85)))

            VStack(alignment: .leading, spacing: 2) {
                Text(mode.displayName)
                    .font(.subheadline.weight(.semibold))
                Text("Your community is currently in this mode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
        )
    }

    // MARK: - Pinned Covenants Rail

    private var pinnedCovenantsRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                if service.covenants.isEmpty {
                    emptyStateCard(
                        icon: "plus.circle.dashed",
                        message: "No communities yet.\nDiscover and join a Covenant."
                    )
                } else {
                    ForEach(service.covenants) { covenant in
                        NavigationLink(value: covenant) {
                            CovenantPillCard(covenant: covenant)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Continue Rail

    private var continueRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(vm.continueItems) { item in
                    ContinueWhereLeftOffCard(item: item)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Digest Card

    private var digestCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "newspaper.fill")
                    .foregroundStyle(.purple)
                Text("Your daily spiritual digest is ready.")
                    .font(.subheadline)
                Spacer()
                Button("Read") {
                    showDigestSheet = true
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.purple)
            }
            Text("4 new posts · 2 prayer updates · 1 event")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
        )
        .padding(.horizontal, 20)
    }

    // MARK: - Prayer Follow-up Rail

    private var prayerFollowUpRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(service.prayerRequests.prefix(5)) { request in
                    AmenPrayerFollowUpCard(request: request)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Events Rail

    private var eventsRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(vm.upcomingEvents) { event in
                    CovenantEventCard(event: event)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Mentioned Rooms Rail

    private var mentionedRoomsRail: some View {
        VStack(spacing: 0) {
            ForEach(vm.mentionedRooms) { room in
                MentionedRoomRow(room: room)
                Divider().padding(.leading, 58)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .padding(.horizontal, 20)
    }

    // MARK: - New Paid Posts Rail

    private var newPaidPostsRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                if vm.newPaidPosts.isEmpty {
                    emptyStateCard(icon: "doc.richtext", message: "No new posts yet.")
                } else {
                    ForEach(vm.newPaidPosts) { post in
                        NewPaidPostCard(post: post)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Suggested Creators Rail

    private var suggestedCreatorsRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                if vm.suggestedCreators.isEmpty {
                    emptyStateCard(icon: "person.crop.circle.badge.plus", message: "Suggestions loading…")
                } else {
                    ForEach(vm.suggestedCreators) { creator in
                        SuggestedCreatorCard(creator: creator)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Empty State Card

    private func emptyStateCard(icon: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.systemScaled(28))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 160, height: 100)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

// MARK: - Scroll Offset Preference Key

private struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Pill Card

private struct CovenantPillCard: View {
    let covenant: Covenant

    var body: some View {
        VStack(spacing: 8) {
            AsyncImage(url: URL(string: covenant.avatarURL ?? "")) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.purple.opacity(0.2)
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))

            Text(covenant.name)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .frame(width: 72)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
        )
    }
}

// MARK: - Continue Item Models + Card

struct ContinueItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let covenantId: String
    let roomId: String?
}

private struct ContinueWhereLeftOffCard: View {
    let item: ContinueItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: item.icon)
                .font(.systemScaled(22))
                .foregroundStyle(.purple)
            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Text(item.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(16)
        .frame(width: 160)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

// MARK: - Event Card Stub

struct CovenantEventItem: Identifiable {
    let id: String
    let title: String
    let date: Date
    let covenantName: String
}

private struct CovenantEventCard: View {
    let event: CovenantEventItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(event.date, style: .date)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            Text(event.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Text(event.covenantName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 180)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

// MARK: - Mentioned Room Row

private struct MentionedRoomRow: View {
    let room: CovenantRoom

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: room.type.icon)
                .font(.systemScaled(16))
                .foregroundStyle(.purple)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.purple.opacity(0.1)))

            VStack(alignment: .leading, spacing: 2) {
                Text(room.name)
                    .font(.subheadline.weight(.medium))
                if let last = room.lastMessage {
                    Text(last)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()

            if room.unreadCount > 0 {
                Text("\(room.unreadCount)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.red))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - New Paid Post Stub

struct NewPaidPostItem: Identifiable {
    let id: String
    let title: String
    let creatorName: String
    let creatorAvatarURL: String?
    let covenantId: String
}

private struct NewPaidPostCard: View {
    let post: NewPaidPostItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AsyncImage(url: URL(string: post.creatorAvatarURL ?? "")) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color.purple.opacity(0.2)
                }
                .frame(width: 28, height: 28)
                .clipShape(Circle())

                Text(post.creatorName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)

                Spacer()
                Image(systemName: "crown.fill")
                    .font(.systemScaled(10))
                    .foregroundStyle(.yellow)
            }

            Text(post.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(3)
        }
        .padding(14)
        .frame(width: 200)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

// MARK: - Suggested Creator Stub

struct SuggestedCreatorItem: Identifiable {
    let id: String
    let displayName: String
    let tagline: String
    let avatarURL: String?
    let badges: [TrustBadgeType]
}

private struct SuggestedCreatorCard: View {
    let creator: SuggestedCreatorItem
    @State private var isFollowed = false
    @State private var isWritingFollow = false

    var body: some View {
        VStack(spacing: 10) {
            AsyncImage(url: URL(string: creator.avatarURL ?? "")) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Color.purple.opacity(0.15)
            }
            .frame(width: 60, height: 60)
            .clipShape(Circle())

            Text(creator.displayName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(creator.tagline)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            HStack(spacing: 4) {
                ForEach(creator.badges.prefix(2), id: \.self) { badge in
                    AmenTrustBadge(type: badge, size: .compact)
                }
            }

            Button {
                guard !isFollowed, !isWritingFollow else { return }
                withAnimation(.spring(response: 0.3)) { isFollowed = true }
                persistFollow()
            } label: {
                Text(isFollowed ? "Following" : "Follow")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isFollowed ? Color(uiColor: .label) : .white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 7)
                    .background {
                        if isFollowed {
                            Capsule().stroke(Color(uiColor: .separator), lineWidth: 1.5)
                        } else {
                            Capsule().fill(Color.purple)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFollowed ? "Following \(creator.displayName)" : "Follow \(creator.displayName)")
        }
        .padding(16)
        .frame(width: 160)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private func persistFollow() {
        guard let uid = FirebaseAuth.Auth.auth().currentUser?.uid else { return }
        isWritingFollow = true
        let db = Firestore.firestore()
        let docId = "\(uid)_\(creator.id)"
        db.collection("covenantFollows").document(docId).setData([
            "followerId": uid,
            "creatorId": creator.id,
            "creatorDisplayName": creator.displayName,
            "createdAt": FieldValue.serverTimestamp()
        ]) { _ in
            DispatchQueue.main.async { isWritingFollow = false }
        }
    }
}

// MARK: - Daily Digest Sheet

struct CovenantDailyDigestSheet: View {
    let postCount: Int
    let prayerUpdateCount: Int
    let eventCount: Int
    @Environment(\.dismiss) private var dismiss

    private let sections: [(icon: String, label: String, value: Int)] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("\(postCount) new posts from your communities", systemImage: "doc.richtext.fill")
                        .font(.subheadline)
                    Label("\(prayerUpdateCount) prayer request updates", systemImage: "hands.sparkles.fill")
                        .font(.subheadline)
                    Label("\(eventCount) upcoming event", systemImage: "calendar")
                        .font(.subheadline)
                } header: {
                    Text("Today's Activity")
                }

                Section {
                    Text("Open your pinned communities to see the latest posts and join ongoing conversations.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Catch Up")
                }
            }
            .navigationTitle("Daily Digest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Home View Model

@MainActor
final class AmenCovenantHomeViewModel: ObservableObject {
    @Published var continueItems: [ContinueItem] = []
    @Published var upcomingEvents: [CovenantEventItem] = []
    @Published var mentionedRooms: [CovenantRoom] = []
    @Published var newPaidPosts: [NewPaidPostItem] = []
    @Published var suggestedCreators: [SuggestedCreatorItem] = []
    @Published var unreadActivityCount: Int = 0
    @Published var activeMode: CovenantOperatingMode?

    func load() async {
        // Unread count from shared service activities
        let service = CovenantService.shared
        unreadActivityCount = service.activities.filter { !$0.isRead }.count

        // Seed continue items from rooms with recent activity
        continueItems = service.rooms.filter { $0.lastMessageAt != nil }.prefix(5).map { room in
            ContinueItem(
                id: room.id ?? UUID().uuidString,
                title: room.name,
                subtitle: room.lastMessage ?? "No recent messages",
                icon: room.type.icon,
                covenantId: room.covenantId,
                roomId: room.id
            )
        }

        // Mentioned rooms = rooms with unread > 0
        mentionedRooms = Array(service.rooms.filter { $0.unreadCount > 0 }.prefix(5))
    }
}
