//
//  AMENConnectView.swift
//  AMENAPP
//
//  Amen Connect launches from Resources and owns its internal spatial navigation.
//

import SwiftUI
import FirebaseFirestore
import FirebaseFunctions

// MARK: - Compatibility Entry

struct AMENConnectView: View {
    var body: some View {
        AmenConnectRootView()
    }
}

struct AmenConnectRootView: View {
    @StateObject private var viewModel = AmenConnectViewModel()
    @State private var scrollOffset: CGFloat = 0

    private var visibleRooms: [AmenConnectRoom] {
        [.lobby, .discover, .spaces, .dms, .activity, .announcements, .discussions, .meetings, .calendar, .boards, .marketplace, .creators, .safety, .admin]
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AmenConnectSpatialBackground()

            ScrollView {
                GeometryReader { proxy in
                    Color.clear.preference(key: AmenConnectScrollOffsetKey.self, value: proxy.frame(in: .named("AmenConnectScroll")).minY)
                }
                .frame(height: 0)

                VStack(spacing: 16) {
                    AmenConnectGlassHeader(scrollOpacity: min(max(-scrollOffset / 360, 0), 0.10)) {
                        viewModel.isShowingCatchUp = true
                    } onProfile: {
                        viewModel.selectedRoom = .creators
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    AmenConnectRoomSwitcher(selectedRoom: $viewModel.selectedRoom, rooms: visibleRooms)
                        .padding(.horizontal, 16)

                    roomContent
                        .padding(.bottom, 92)
                }
            }
            .coordinateSpace(name: "AmenConnectScroll")
            .onPreferenceChange(AmenConnectScrollOffsetKey.self) { scrollOffset = $0 }

            AmenConnectFloatingActionButton {
                viewModel.isShowingCommandSheet = true
            }
            .padding(.trailing, 20)
            .padding(.bottom, 24)
        }
        .navigationTitle("Amen Connect")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .sheet(isPresented: $viewModel.isShowingCatchUp) {
            AmenConnectAICatchUpSheet(activityItems: viewModel.activityItems)
        }
        .sheet(isPresented: $viewModel.isShowingCommandSheet) {
            AmenConnectAICommandSheet(contracts: viewModel.backendContracts)
        }
    }

    @ViewBuilder
    private var roomContent: some View {
        switch viewModel.selectedRoom {
        case .lobby:
            AmenConnectLobbyView(viewModel: viewModel)
        case .discover:
            AmenConnectDiscoverView(viewModel: viewModel)
        case .spaces:
            AmenConnectSpaceListView(viewModel: viewModel)
        case .dms:
            AmenConnectDMsView()
        case .activity:
            AmenConnectActivityView(items: viewModel.activityItems)
        case .announcements:
            AmenConnectAnnouncementsView()
        case .discussions:
            AmenConnectChannelListView(channels: viewModel.channels)
        case .meetings:
            AmenConnectMeetingsView(meetings: viewModel.meetings)
        case .calendar:
            AmenConnectCalendarView(meetings: viewModel.meetings)
        case .boards:
            AmenConnectBoardsView(boards: viewModel.boards)
        case .marketplace:
            AmenConnectMarketplaceView(listings: viewModel.listings)
        case .creators:
            AmenConnectCreatorDirectoryView(viewModel: viewModel)
        case .safety:
            AmenConnectSafetyCenterView(contracts: viewModel.backendContracts)
        case .admin:
            AmenConnectAdminView(contracts: viewModel.backendContracts)
        }
    }
}

private struct AmenConnectScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct AmenConnectSpatialBackground: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color(red: 0.91, green: 0.96, blue: 1.0), Color.white, Color(red: 0.98, green: 0.98, blue: 0.96)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 340)
                Spacer()
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - Lobby

struct AmenConnectLobbyView: View {
    @ObservedObject var viewModel: AmenConnectViewModel

    // Disambiguation routing state
    @State private var showBereanSheet = false
    @State private var bereanInitialQuery: String = ""
    @State private var showFindChurch = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Amen Connect")
                    .font(.systemScaled(36, weight: .black))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("Community spaces, announcements, discussions, meetings, events, jobs, mentorship, resources, and safe group communication.")
                    .font(.systemScaled(15))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)

            AmenConnectSearchCapsule(
                placeholder: "Search spaces, DMs, jobs, boards, creators",
                text: $viewModel.searchText,
                onBereanAI: { query in
                    bereanInitialQuery = query
                    showBereanSheet = true
                },
                onFindChurch: {
                    showFindChurch = true
                }
            )
            .padding(.horizontal, 20)

            AmenConnectPriorityPanel(items: viewModel.activityItems) {
                viewModel.isShowingCatchUp = true
            }
            .padding(.horizontal, 20)

            AmenConnectSectionGrid(viewModel: viewModel)
                .padding(.horizontal, 20)
        }
        .sheet(isPresented: $showBereanSheet) {
            if bereanInitialQuery.isEmpty {
                BereanChatView()
            } else {
                BereanChatView(initialQuery: bereanInitialQuery)
                    .onAppear { bereanInitialQuery = "" }
            }
        }
        .sheet(isPresented: $showFindChurch) {
            ChurchSearchView()
        }
    }
}

private struct AmenConnectPriorityPanel: View {
    var items: [AmenConnectActivityItem]
    var catchUpAction: () -> Void

    var body: some View {
        AmenConnectCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Here is what matters", systemImage: "sparkles")
                        .font(.systemScaled(17, weight: .bold))
                    Spacer()
                    Button("Catch Up", action: catchUpAction)
                        .font(.systemScaled(13, weight: .semibold))
                }
                ForEach(items.prefix(5)) { item in
                    HStack(alignment: .top, spacing: 9) {
                        Circle()
                            .fill(item.isPriority ? Color.red : Color.blue)
                            .frame(width: 7, height: 7)
                            .padding(.top, 7)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.systemScaled(14, weight: .semibold))
                            Text(item.detail)
                                .font(.systemScaled(12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Text("AI-assisted summaries exclude private, paid, youth-protected, deleted, confidential, and admin-excluded content.")
                    .font(.systemScaled(11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("AI summaries are permission aware and exclude restricted content")
            }
        }
    }
}

private struct AmenConnectSectionGrid: View {
    @ObservedObject var viewModel: AmenConnectViewModel

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            sectionCard("Spaces", icon: "square.grid.2x2", detail: "\(viewModel.spaces.count) workspaces", room: .spaces)
            sectionCard("Announcements", icon: "megaphone", detail: "Pinned, urgent, scheduled", room: .announcements)
            sectionCard("Discussions", icon: "number", detail: "Channels, threads, reactions", room: .discussions)
            sectionCard("Meetings", icon: "video", detail: "Huddles, rooms, recaps", room: .meetings)
            sectionCard("Calendar", icon: "calendar", detail: "Events, RSVPs, bookings", room: .calendar)
            sectionCard("Marketplace", icon: "storefront", detail: "Jobs, babysitting, help", room: .marketplace)
            sectionCard("Creators", icon: "person.crop.rectangle.stack", detail: "Tiers, posts, products", room: .creators)
            sectionCard("Safety", icon: "shield.checkered", detail: "Reports and AI guardrails", room: .safety)
        }
    }

    private func sectionCard(_ title: String, icon: String, detail: String, room: AmenConnectRoom) -> some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                viewModel.selectedRoom = room
            }
        } label: {
            AmenConnectCard {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color(.systemGray6)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.systemScaled(15, weight: .bold))
                            .foregroundStyle(.primary)
                        Text(detail)
                            .font(.systemScaled(12))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(title)")
    }
}

// MARK: - Discover

struct AmenConnectDiscoverView: View {
    @ObservedObject var viewModel: AmenConnectViewModel
    @State private var selectedFilter = "All"
    private let filters = ["All", "Faith", "College", "Career", "Lifestyle", "Parenting", "Finance", "Health", "Music", "Creative", "Jobs", "Babysitting", "Tutoring", "Mentorship", "Local Help", "Events", "Organizations"]

    // Listings whose category.rawValue matches the selected filter, or all when "All".
    private var filteredListings: [AmenConnectMarketplaceListing] {
        guard selectedFilter != "All" else { return viewModel.listings }
        return viewModel.listings.filter { listing in
            listing.category.rawValue.caseInsensitiveCompare(selectedFilter) == .orderedSame
        }
    }

    // Creators filtered by type or keyword match in bio/type rawValue.
    private var filteredCreators: [AmenConnectCreatorProfile] {
        guard selectedFilter != "All" else { return viewModel.creators }
        let keyword = selectedFilter.lowercased()
        return viewModel.creators.filter { creator in
            switch selectedFilter {
            case "Organizations": return creator.type == .organization || creator.type == .nonprofit
            case "College":       return creator.type == .collegeUniversityGroup
            case "Mentorship":    return creator.type == .mentor
            case "Tutoring":      return creator.type == .tutor
            default:
                return creator.type.rawValue.lowercased().contains(keyword) ||
                       creator.bio.lowercased().contains(keyword)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AmenConnectRoomTitle(title: "Discover", subtitle: "Find communities, mentors, jobs, trusted local help, events, cohorts, and creators.")
            AmenConnectFilterChips(filters: filters, selected: $selectedFilter)
                .padding(.horizontal, 20)
            if !filteredCreators.isEmpty {
                horizontalCreatorSection(title: "Based on your memberships", creators: filteredCreators)
                horizontalCreatorSection(title: "Creators for you", creators: filteredCreators)
            }
            if !filteredListings.isEmpty {
                AmenConnectListingSection(title: "Jobs, babysitters, tutoring, and trusted local help", listings: filteredListings)
            }
            if filteredCreators.isEmpty && filteredListings.isEmpty && selectedFilter != "All" {
                AmenConnectCard {
                    VStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(.secondary)
                        Text("No results for \"\(selectedFilter)\"")
                            .font(.systemScaled(15, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .padding(.horizontal, 20)
            }
            AmenConnectSpaceSection(title: "University groups near you", spaces: viewModel.spaces)
        }
    }

    private func horizontalCreatorSection(title: String, creators: [AmenConnectCreatorProfile]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.systemScaled(18, weight: .bold))
                .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(creators) { creator in
                        AmenConnectCreatorCard(creator: creator)
                            .frame(width: 260)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

// MARK: - Room Views

struct AmenConnectSpaceListView: View {
    @ObservedObject var viewModel: AmenConnectViewModel
    @State private var communities: [SpacesCommunity] = []
    @State private var isLoading = true
    @State private var showCreationWizard = false
    @State private var selectedCommunity: SpacesCommunity? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header + Create button
            HStack(alignment: .top) {
                AmenConnectRoomTitle(
                    title: "Spaces",
                    subtitle: "Community workspaces for churches, ministries, colleges, and groups."
                )
                Spacer()
                Button {
                    showCreationWizard = true
                } label: {
                    Label("New", systemImage: "plus")
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(AmenTheme.Colors.amenPurple))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Create a new community")
                .padding(.trailing, 20)
                .padding(.top, 4)
            }

            // Community list
            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .padding(.vertical, 32)
            } else if communities.isEmpty {
                AmenConnectCard {
                    VStack(spacing: 14) {
                        Image(systemName: "person.3")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(.secondary)
                        Text("No Communities Yet")
                            .font(.systemScaled(16, weight: .semibold))
                        Text("Create or join a community to get started.")
                            .font(.systemScaled(13))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button {
                            showCreationWizard = true
                        } label: {
                            Label("Create a Community", systemImage: "plus")
                                .font(.systemScaled(14, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Capsule().fill(AmenTheme.Colors.amenPurple))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Create a new community")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .padding(.horizontal, 20)
            } else {
                ForEach(communities) { community in
                    Button {
                        selectedCommunity = community
                    } label: {
                        AmenConnectCard {
                            HStack(spacing: 14) {
                                SpaceAvatarView(
                                    avatarURL: community.avatarURL,
                                    title: community.name,
                                    size: 40,
                                    isShared: false
                                )
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(community.name)
                                        .font(.systemScaled(16, weight: .bold))
                                        .foregroundStyle(.primary)
                                    Text("@\(community.handle)")
                                        .font(.systemScaled(12))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(community.name)")
                    .padding(.horizontal, 20)
                }

                // Create another community
                Button {
                    showCreationWizard = true
                } label: {
                    AmenConnectCard {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(AmenTheme.Colors.amenPurple.opacity(0.12))
                                .frame(width: 40, height: 40)
                                .overlay(Image(systemName: "plus").foregroundStyle(AmenTheme.Colors.amenPurple).font(.system(size: 16, weight: .semibold)))
                            Text("Create a new community")
                                .font(.systemScaled(15, weight: .medium))
                                .foregroundStyle(AmenTheme.Colors.amenPurple)
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
            }
        }
        .task { await loadCommunities() }
        .sheet(isPresented: $showCreationWizard) {
            SpaceCreationWizard(communityId: "")
        }
        .sheet(item: $selectedCommunity) { community in
            NavigationStack {
                SpacesListView(communityId: community.communityId)
                    .navigationTitle(community.name)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private func loadCommunities() async {
        isLoading = true
        do {
            communities = try await SpacesService.shared.fetchMyCommunities()
        } catch {
            communities = []
        }
        isLoading = false
    }
}

struct AmenConnectChannelListView: View {
    var channels: [AmenConnectChannel]
    @State private var bereanQuery: String = ""
    @State private var showBerean = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AmenConnectRoomTitle(title: "Amen Channels", subtitle: "Public, private, announcement, marketplace, meeting, study, volunteer, youth-protected, and paid-member channels.")
            VStack(spacing: 10) {
                ForEach(channels) { channel in
                    Button {
                        bereanQuery = "#\(channel.name)"
                        showBerean = true
                    } label: {
                        AmenConnectCard {
                            HStack(spacing: 12) {
                                Image(systemName: channel.visibility == .confidential ? "lock.fill" : "number")
                                    .frame(width: 30)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("#\(channel.name)")
                                        .font(.systemScaled(16, weight: .bold))
                                    Text(channel.pinnedMessage ?? "Threads, mentions, reactions, polls, pinned messages, files, and AI summaries.")
                                        .font(.systemScaled(12))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if channel.unreadCount > 0 {
                                    Text("\(channel.unreadCount)")
                                        .font(.systemScaled(12, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(Color.red))
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open channel #\(channel.name)\(channel.unreadCount > 0 ? ", \(channel.unreadCount) unread" : "")")
                    .padding(.horizontal, 20)
                }
            }
        }
        .sheet(isPresented: $showBerean) {
            BereanChatView(initialQuery: bereanQuery)
                .onAppear { bereanQuery = "" }
        }
    }
}

struct AmenConnectDMsView: View {
    private let filters = ["All", "Direct Messages", "Group Chats", "VIP", "Requests", "External", "Marketplace", "Mentorship"]
    @State private var selected = "All"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AmenConnectRoomTitle(title: "DMs", subtitle: "Personal DMs, group DMs, message requests, VIP filters, safe contact controls, and marketplace conversation warnings.")
            AmenConnectFilterChips(filters: filters, selected: $selected)
                .padding(.horizontal, 20)
            AmenConnectFeatureList(items: [
                ("Message requests", "Untrusted external contact starts here before a DM opens."),
                ("Youth/minor restrictions", "Safe contact, no unsolicited sensitive media, guardian controls where required."),
                ("AI conversation summary", "Summaries only use messages this user may access and skips excluded content."),
                ("Block and report", "Every DM has block, report, and safety escalation contracts.")
            ])
        }
    }
}

struct AmenConnectActivityView: View {
    var items: [AmenConnectActivityItem]
    @State private var selected = "All"
    private let filters = ["All", "Mentions", "Threads", "Announcements", "Meetings", "Tasks", "Marketplace", "Memberships", "Safety", "VIP"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AmenConnectRoomTitle(title: "Amen Pulse", subtitle: "Mentions, threads, announcements, meetings, tasks, marketplace, memberships, safety, and AI catch-up.")
            AmenConnectFilterChips(filters: filters, selected: $selected)
                .padding(.horizontal, 20)
            ForEach(items) { item in
                AmenConnectCard {
                    HStack(spacing: 12) {
                        Image(systemName: item.requiresAction ? "exclamationmark.circle.fill" : item.room.iconName)
                            .foregroundStyle(item.isPriority ? .red : .blue)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.systemScaled(15, weight: .bold))
                            Text(item.detail)
                                .font(.systemScaled(12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

struct AmenConnectAnnouncementsView: View {
    var body: some View {
        AmenConnectFeatureRoom(
            title: "Announcements",
            subtitle: "Outlook-priority and Teams-style broadcast messages.",
            features: [
                ("Pinned and urgent", "Scheduled announcements, expiration, audience targeting, and read receipts."),
                ("AI rewrite and translation", "Permission-aware drafts with AI-assisted labels."),
                ("Safety before publish", "Monetized, youth-facing, urgent, and coercive content routes through moderation."),
                ("Audit logs", "Publish, edit, target, and moderation events are server-authoritative.")
            ]
        )
    }
}

struct AmenConnectMeetingsView: View {
    var meetings: [AmenConnectMeeting]
    @State private var selectedMeeting: AmenConnectMeeting? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AmenConnectRoomTitle(title: "Amen Meetings", subtitle: "Huddles, study rooms, office hours, webinars, paid live sessions, attendance, transcripts, and recaps.")
            ForEach(meetings) { meeting in
                Button {
                    selectedMeeting = meeting
                } label: {
                    AmenConnectCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label(meeting.type, systemImage: meeting.isPaid ? "ticket.fill" : "video.fill")
                                    .font(.systemScaled(12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(meeting.startsIn)
                                    .font(.systemScaled(12, weight: .bold))
                                    .foregroundStyle(.blue)
                            }
                            Text(meeting.title)
                                .font(.systemScaled(18, weight: .bold))
                            Text("Hosted by \(meeting.hostName) · \(meeting.attendeeCount) attending · waiting room, host controls, recording consent, report flow, and AI recap contract.")
                                .font(.systemScaled(13))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View meeting: \(meeting.title), starts \(meeting.startsIn)")
                .padding(.horizontal, 20)
            }
        }
        .sheet(item: $selectedMeeting) { meeting in
            AmenConnectMeetingDetailSheet(meeting: meeting)
        }
    }
}

struct AmenConnectCalendarView: View {
    var meetings: [AmenConnectMeeting]
    @State private var selected = "Today"
    private let filters = ["Today", "Week", "Month", "My Commitments", "Space Events", "Marketplace Bookings", "Volunteer Shifts", "Live Sessions", "Office Hours"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AmenConnectRoomTitle(title: "Amen Calendar", subtitle: "Personal and Space calendars for meetings, events, RSVPs, bookings, shifts, reminders, and paid sessions.")
            AmenConnectFilterChips(filters: filters, selected: $selected)
                .padding(.horizontal, 20)
            AmenConnectFeatureList(items: [
                ("UCF Ministry Study Room", "Starts in 20 minutes · 34 attending · event chat enabled."),
                ("Babysitting booking request", "Pending verification before exact location is visible."),
                ("Volunteer shift", "Saturday 9:00 AM · RSVP and reminders enabled."),
                ("AI scheduling assistant", "Finds permitted times and never exposes private calendar details.")
            ])
        }
    }
}

struct AmenConnectBoardsView: View {
    var boards: [AmenConnectBoard]
    @State private var selectedBoard: AmenConnectBoard? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AmenConnectRoomTitle(title: "Amen Boards", subtitle: "Notion-style dashboards, pages, resources, templates, onboarding, cohort, class, ministry, and marketplace boards.")
            ForEach(boards) { board in
                Button {
                    selectedBoard = board
                } label: {
                    AmenConnectCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(board.title)
                                    .font(.systemScaled(17, weight: .bold))
                                Spacer()
                                Text(board.visibility == .paidTier ? "Paid" : "Open")
                                    .font(.systemScaled(11, weight: .bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color(.systemGray6)))
                            }
                            Text(board.blocks.joined(separator: " · "))
                                .font(.systemScaled(13))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open board: \(board.title)")
                .padding(.horizontal, 20)
            }
        }
        .sheet(item: $selectedBoard) { board in
            AmenConnectBoardDetailSheet(board: board)
        }
    }
}

struct AmenConnectMarketplaceView: View {
    var listings: [AmenConnectMarketplaceListing]
    @State private var selected = "All"
    private let filters = ["All", "Jobs", "Babysitting", "Tutoring", "Services", "Rides", "Housing", "Volunteering", "Mentorship", "Items", "Local Help", "Digital Products", "Paid Events", "Bookings"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AmenConnectRoomTitle(title: "Amen Marketplace", subtitle: "Trusted jobs, babysitting, tutoring, services, rides, housing, volunteering, mentorship, items, local help, products, sessions, and bookings.")
            AmenConnectFilterChips(filters: filters, selected: $selected)
                .padding(.horizontal, 20)
            AmenConnectListingSection(title: "Safety-reviewed opportunities", listings: listings)
            AmenConnectFeatureList(items: [
                ("Marketplace safety", "Identity, trust badges, report listing/user, expiration, location privacy, scam and off-platform pressure detection."),
                ("Babysitting controls", "Parent/guardian posting, sitter applications, approximate location, verified sitter badges, guardian approval, and safe contact."),
                ("Job moderation", "Verified organizations, expiration, vague listing, exploitative pay, and scam detection contracts.")
            ])
        }
    }
}

struct AmenConnectCreatorDirectoryView: View {
    @ObservedObject var viewModel: AmenConnectViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AmenConnectRoomTitle(title: "Creator and Leader Profiles", subtitle: "Amen-native trusted community economy for creators, mentors, teachers, tutors, babysitters, coaches, organizations, and service providers.")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.creators) { creator in
                        AmenConnectCreatorCard(creator: creator)
                            .frame(width: 280)
                    }
                }
                .padding(.horizontal, 20)
            }
            AmenConnectMembershipTiersView(tiers: viewModel.tiers)
            AmenConnectFeatureList(items: [
                ("Smart Tier Builder", "AI suggests tier names, pricing, benefits, access rules, safe boundaries, cadence, refund language, and onboarding."),
                ("Posts and collections", "Public, member-only, tier-specific posts, comments, reactions, scheduled posts, translations, and resource collections."),
                ("Products and bookings", "Digital products, paid sessions, mentorship, tutoring, babysitting, consulting, courses, and replay access use server-authoritative purchase state."),
                ("Leader dashboard", "Members, paid members, revenue contracts, engagement, top posts, attendance, safety reports, and AI recommendations.")
            ])
        }
    }
}

struct AmenConnectSafetyCenterView: View {
    var contracts: [AmenConnectBackendContract]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AmenConnectRoomTitle(title: "Safety Center", subtitle: "Reports, blocks, youth protections, marketplace safety, AI exclusions, monetization safety, moderation, and audit logs.")
            AmenConnectFeatureList(items: [
                ("AI permission boundary", "AI can only use content the current user can access and skips paid, confidential, deleted, youth-protected, and excluded content."),
                ("Moderation outcomes", "Allow, allow with warning, suggest rewrite, require confirmation, send to moderation, block, escalate, or crisis support."),
                ("Monetization safety", "Flags scams, spiritual coercion, unrealistic guarantees, financial overclaims, unsafe minor contact, predatory pricing, and off-platform payment pressure."),
                ("Marketplace protection", "Jobs, babysitting, tutoring, services, rides, housing, volunteering, mentorship, and local help include trust and audit contracts.")
            ])
            AmenConnectBackendContractPanel(title: "Safety contracts", contracts: contracts.filter { $0.functionName.contains("moderate") || $0.functionName.contains("report") || $0.functionName.contains("CatchUp") })
        }
    }
}

struct AmenConnectAdminView: View {
    var contracts: [AmenConnectBackendContract]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AmenConnectRoomTitle(title: "Admin", subtitle: "Visible only when permitted. Role changes, invites, listing approval, audit logs, trust badges, verification badges, moderation, payment state, and AI summaries are server-authoritative.")
            PendingSpacesAdminSection()
            AmenConnectBackendContractPanel(title: "Cloud Function contracts", contracts: contracts)
        }
    }
}

// MARK: - Pending Spaces Admin Queue

@MainActor
private final class PendingSpacesAdminViewModel: ObservableObject {
    @Published var pendingSpaces: [AMENSpace] = []
    @Published var isLoading = false
    @Published var reviewingIds: Set<String> = []
    @Published var errorBySpaceId: [String: String] = [:]

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    func startListening() {
        guard listener == nil else { return }
        isLoading = true
        listener = db.collection("spaces")
            .whereField("visibility", isEqualTo: "pendingReview")
            .order(by: "createdAt", descending: false)
            .limit(to: 50)
            .addSnapshotListener { [weak self] snap, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isLoading = false
                    if error != nil { return }
                    self.pendingSpaces = snap?.documents.compactMap {
                        try? $0.data(as: AMENSpace.self)
                    } ?? []
                }
            }
    }

    func review(spaceId: String, decision: String) async {
        reviewingIds.insert(spaceId)
        errorBySpaceId.removeValue(forKey: spaceId)
        do {
            _ = try await Functions.functions()
                .httpsCallable(SpacesCallable.reviewSpace.rawValue)
                .call(["spaceId": spaceId, "decision": decision])
        } catch {
            errorBySpaceId[spaceId] = decision == "approve"
                ? "Could not approve. Try again."
                : "Could not reject. Try again."
        }
        reviewingIds.remove(spaceId)
    }

    func stopListening() { listener?.remove(); listener = nil }
    deinit { listener?.remove() }
}

private struct PendingSpacesAdminSection: View {
    @StateObject private var vm = PendingSpacesAdminViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Pending Review")
                    .font(.systemScaled(18, weight: .bold))
                    .padding(.horizontal, 20)
                if !vm.pendingSpaces.isEmpty {
                    Text("\(vm.pendingSpaces.count)")
                        .font(.systemScaled(12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.orange))
                }
                Spacer()
            }

            if vm.isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .padding(.vertical, 20)
            } else if vm.pendingSpaces.isEmpty {
                AmenConnectCard {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("No communities pending review")
                            .font(.systemScaled(14))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)
            } else {
                ForEach(vm.pendingSpaces) { space in
                    PendingSpaceAdminRow(space: space, vm: vm)
                        .padding(.horizontal, 20)
                }
            }
        }
        .onAppear { vm.startListening() }
        .onDisappear { vm.stopListening() }
    }
}

private struct PendingSpaceAdminRow: View {
    let space: AMENSpace
    @ObservedObject var vm: PendingSpacesAdminViewModel

    private var spaceId: String { space.id ?? "" }
    private var isReviewing: Bool { vm.reviewingIds.contains(spaceId) }

    var body: some View {
        AmenConnectCard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(space.name)
                        .font(.systemScaled(16, weight: .bold))
                    Text(space.description)
                        .font(.systemScaled(13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !space.aiDetectedTopics.isEmpty {
                        Text(space.aiDetectedTopics.prefix(4).joined(separator: " · "))
                            .font(.systemScaled(11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    if let createdAt = space.createdAt {
                        Text("Submitted \(createdAt.formatted(.relative(presentation: .named)))")
                            .font(.systemScaled(11))
                            .foregroundStyle(.tertiary)
                    }
                }

                if let errMsg = vm.errorBySpaceId[spaceId] {
                    Label(errMsg, systemImage: "exclamationmark.triangle.fill")
                        .font(.systemScaled(12))
                        .foregroundStyle(.orange)
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await vm.review(spaceId: spaceId, decision: "approve") }
                    } label: {
                        Group {
                            if isReviewing {
                                Label("Approving…", systemImage: "checkmark.circle.fill")
                            } else {
                                Label("Approve", systemImage: "checkmark.circle.fill")
                            }
                        }
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(isReviewing ? Color(.systemGray) : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isReviewing ? Color(.systemGray5) : Color.green)
                        )
                    }
                    .disabled(isReviewing || spaceId.isEmpty)
                    .accessibilityLabel("Approve community: \(space.name)")

                    Button {
                        Task { await vm.review(spaceId: spaceId, decision: "reject") }
                    } label: {
                        Group {
                            if isReviewing {
                                Label("Rejecting…", systemImage: "xmark.circle.fill")
                            } else {
                                Label("Reject", systemImage: "xmark.circle.fill")
                            }
                        }
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(isReviewing ? Color(.systemGray) : .red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isReviewing ? Color(.systemGray5) : Color.red.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(isReviewing ? Color.clear : Color.red.opacity(0.35), lineWidth: 1)
                                )
                        )
                    }
                    .disabled(isReviewing || spaceId.isEmpty)
                    .accessibilityLabel("Reject community: \(space.name)")
                }
            }
        }
    }
}

// MARK: - Sheets

struct AmenConnectAICatchUpSheet: View {
    var activityItems: [AmenConnectActivityItem]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("AI-assisted catch up") {
                    ForEach(activityItems) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.headline)
                            Text(item.detail).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Permission rule") {
                    Text("Amen Guide can summarize only content the current user can access. Paid, private, confidential, youth-protected, deleted, and AI-excluded content is not included unless the user has explicit access and the content permits AI use.")
                }
            }
            .navigationTitle("AI Catch Up")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

struct AmenConnectAICommandSheet: View {
    var contracts: [AmenConnectBackendContract]
    @Environment(\.dismiss) private var dismiss
    @State private var bereanQuery: String = ""
    @State private var showBerean = false

    private struct GuideAction: Identifiable {
        let id: String
        let label: String
        let icon: String
        let query: String
    }

    private let guideActions: [GuideAction] = [
        GuideAction(id: "summarize", label: "Summarize unread messages", icon: "list.bullet.clipboard", query: "Summarize my unread messages and surface the most important items."),
        GuideAction(id: "tasks", label: "Turn chat into tasks", icon: "checklist", query: "Extract action items and tasks from recent discussions."),
        GuideAction(id: "event", label: "Create event from discussion", icon: "calendar.badge.plus", query: "Help me create a community event based on this discussion."),
        GuideAction(id: "announcement", label: "Draft announcement", icon: "megaphone", query: "Help me draft a community announcement."),
        GuideAction(id: "board", label: "Create board from prompt", icon: "rectangle.on.rectangle.angled", query: "Help me create a community board or resource page."),
        GuideAction(id: "job", label: "Create job listing", icon: "briefcase", query: "Help me create a safe, accurate job listing for the marketplace."),
        GuideAction(id: "babysitting", label: "Create babysitting listing", icon: "figure.child", query: "Help me create a babysitting listing with all required safety disclosures."),
        GuideAction(id: "tier", label: "Build safe paid tier", icon: "star.circle", query: "Help me create a membership tier that is fairly priced and spiritually grounded."),
        GuideAction(id: "review", label: "Review monetized offer", icon: "checkmark.shield", query: "Review my monetized offer for safety, fairness, and spiritual alignment."),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Amen Guide actions") {
                    ForEach(guideActions) { action in
                        Button {
                            bereanQuery = action.query
                            dismiss()
                            showBerean = true
                        } label: {
                            Label(action.label, systemImage: action.icon)
                        }
                        .accessibilityLabel(action.label)
                    }
                }
                Section("Backend contracts") {
                    ForEach(contracts.prefix(6)) { contract in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(contract.functionName).font(.headline)
                            Text(contract.purpose).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Amen Guide")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .sheet(isPresented: $showBerean) {
            BereanChatView(initialQuery: bereanQuery)
                .onAppear { bereanQuery = "" }
        }
    }
}

// MARK: - Reusable Local Views

private struct AmenConnectRoomTitle: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.systemScaled(28, weight: .black))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            Text(subtitle)
                .font(.systemScaled(14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
    }
}

private struct AmenConnectCard<Content: View>: View {
    var content: () -> Content

    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color(.separator).opacity(0.28), lineWidth: 0.5))
    }
}

private struct AmenConnectFilterChips: View {
    var filters: [String]
    @Binding var selected: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filters, id: \.self) { filter in
                    AmenConnectGlassPill(title: filter, iconName: nil, isSelected: selected == filter) {
                        selected = filter
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct AmenConnectSpaceSection: View {
    var title: String
    var spaces: [AmenConnectSpace]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.systemScaled(18, weight: .bold))
                .padding(.horizontal, 20)
            ForEach(spaces) { space in
                AmenConnectCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(space.name)
                                    .font(.systemScaled(17, weight: .bold))
                                Text(space.type.rawValue)
                                    .font(.systemScaled(12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if space.unreadCount > 0 {
                                Text("\(space.unreadCount)")
                                    .font(.systemScaled(12, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.red))
                            }
                        }
                        Text(space.description)
                            .font(.systemScaled(13))
                            .foregroundStyle(.secondary)
                        AmenConnectBadgeRow(badges: space.trustBadges)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

private struct AmenConnectListingSection: View {
    var title: String
    var listings: [AmenConnectMarketplaceListing]
    @State private var selectedListing: AmenConnectMarketplaceListing? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.systemScaled(18, weight: .bold))
                .padding(.horizontal, 20)
            ForEach(listings) { listing in
                Button {
                    selectedListing = listing
                } label: {
                    AmenConnectCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(listing.title)
                                        .font(.systemScaled(16, weight: .bold))
                                    Text("\(listing.category.rawValue) · \(listing.locationLabel)")
                                        .font(.systemScaled(12))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(listing.compensation)
                                    .font(.systemScaled(12, weight: .bold))
                            }
                            Text("\(listing.posterName) · \(listing.verificationLevel) · \(listing.expiresLabel)")
                                .font(.systemScaled(12))
                                .foregroundStyle(.secondary)
                            AmenConnectBadgeRow(badges: listing.trustBadges)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View listing: \(listing.title), \(listing.category.rawValue), \(listing.compensation)")
                .padding(.horizontal, 20)
            }
        }
        .sheet(item: $selectedListing) { listing in
            AmenConnectListingDetailSheet(listing: listing)
        }
    }
}

private struct AmenConnectCreatorCard: View {
    var creator: AmenConnectCreatorProfile
    @State private var showDetail = false

    var body: some View {
        Button {
            showDetail = true
        } label: {
            AmenConnectCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(colors: [Color.blue.opacity(0.25), Color.green.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 58, height: 58)
                            .overlay(Image(systemName: "person.crop.rectangle.stack").foregroundStyle(.primary))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(creator.displayName)
                                .font(.systemScaled(16, weight: .bold))
                                .lineLimit(2)
                            Text(creator.type.rawValue.capitalized)
                                .font(.systemScaled(12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(creator.bio)
                        .font(.systemScaled(13))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    HStack {
                        Text("\(creator.memberCount) members")
                        Text(creator.isPaidEnabled ? "Free + paid" : "Free")
                        if let liveSoonLabel = creator.liveSoonLabel { Text(liveSoonLabel) }
                    }
                    .font(.systemScaled(11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    AmenConnectBadgeRow(badges: creator.trustBadges)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View profile: \(creator.displayName), \(creator.type.rawValue)")
        .sheet(isPresented: $showDetail) {
            AmenConnectCreatorDetailSheet(creator: creator)
        }
    }
}

struct AmenConnectMembershipTiersView: View {
    var tiers: [AmenConnectMembershipTier]
    @State private var selectedTier: AmenConnectMembershipTier? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Memberships")
                .font(.systemScaled(18, weight: .bold))
                .padding(.horizontal, 20)
            ForEach(tiers) { tier in
                Button {
                    selectedTier = tier
                } label: {
                    AmenConnectCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(tier.name).font(.systemScaled(16, weight: .bold))
                                Spacer()
                                Text(tier.priceLabel).font(.systemScaled(13, weight: .bold))
                            }
                            Text(tier.benefits.joined(separator: " · "))
                                .font(.systemScaled(12))
                                .foregroundStyle(.secondary)
                            if !tier.safetyFlags.isEmpty {
                                Text("Safety: \(tier.safetyFlags.joined(separator: " · "))")
                                    .font(.systemScaled(11, weight: .medium))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View membership tier: \(tier.name), \(tier.priceLabel)")
                .padding(.horizontal, 20)
            }
        }
        .sheet(item: $selectedTier) { tier in
            AmenConnectTierDetailSheet(tier: tier)
        }
    }
}

private struct AmenConnectBadgeRow: View {
    var badges: [AmenConnectTrustBadge]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(badges) { badge in
                    Label(badge.rawValue, systemImage: "checkmark.seal.fill")
                        .font(.systemScaled(10, weight: .semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.green.opacity(0.10)))
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AmenConnectFeatureRoom: View {
    var title: String
    var subtitle: String
    var features: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AmenConnectRoomTitle(title: title, subtitle: subtitle)
            AmenConnectFeatureList(items: features)
        }
    }
}

private struct AmenConnectFeatureList: View {
    var items: [(String, String)]

    var body: some View {
        ForEach(items, id: \.0) { item in
            AmenConnectCard {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.0)
                        .font(.systemScaled(16, weight: .bold))
                    Text(item.1)
                        .font(.systemScaled(13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

private struct AmenConnectBackendContractPanel: View {
    var title: String
    var contracts: [AmenConnectBackendContract]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.systemScaled(18, weight: .bold))
                .padding(.horizontal, 20)
            ForEach(contracts) { contract in
                AmenConnectCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(contract.functionName)
                            .font(.systemScaled(15, weight: .bold))
                        Text(contract.purpose)
                            .font(.systemScaled(12))
                            .foregroundStyle(.secondary)
                        Text("Server-owned: \(contract.serverAuthoritativeFields.joined(separator: ", "))")
                            .font(.systemScaled(11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

struct AMENConnectEntryCard: View {
    var body: some View {
        AmenConnectCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "person.3.fill")
                        .font(.systemScaled(20))
                        .foregroundStyle(.blue)
                    Text("Amen Connect")
                        .font(.systemScaled(18, weight: .bold))
                }
                Text("Community spaces, announcements, discussions, meetings, events, jobs, help, and safe group communication.")
                    .font(.systemScaled(14))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Inline Detail Sheets (no standalone detail view exists for these model types)

struct AmenConnectMeetingDetailSheet: View {
    let meeting: AmenConnectMeeting
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AmenConnectCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(meeting.type, systemImage: meeting.isPaid ? "ticket.fill" : "video.fill")
                                .font(.systemScaled(13, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(meeting.title)
                                .font(.systemScaled(22, weight: .black))
                            HStack(spacing: 8) {
                                Label("Starts \(meeting.startsIn)", systemImage: "clock")
                                Spacer()
                                Label("\(meeting.attendeeCount) attending", systemImage: "person.2")
                            }
                            .font(.systemScaled(13))
                            .foregroundStyle(.secondary)
                            Text("Hosted by \(meeting.hostName)")
                                .font(.systemScaled(14, weight: .semibold))
                        }
                    }
                    AmenConnectCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Safety & Controls", systemImage: "shield.checkered")
                                .font(.systemScaled(15, weight: .bold))
                            Text("Waiting room · Host controls · Recording consent required · In-meeting report flow · AI recap with permission boundary.")
                                .font(.systemScaled(13))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .navigationTitle("Meeting Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

struct AmenConnectBoardDetailSheet: View {
    let board: AmenConnectBoard
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AmenConnectCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(board.title)
                                    .font(.systemScaled(22, weight: .black))
                                Spacer()
                                Text(board.visibility == .paidTier ? "Paid" : "Open")
                                    .font(.systemScaled(12, weight: .bold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(Color(.systemGray5)))
                            }
                            Text("Type: \(board.type)")
                                .font(.systemScaled(13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    AmenConnectCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Blocks")
                                .font(.systemScaled(15, weight: .bold))
                            ForEach(board.blocks, id: \.self) { block in
                                Label(block, systemImage: "square.on.square")
                                    .font(.systemScaled(13))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .navigationTitle("Board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

struct AmenConnectListingDetailSheet: View {
    let listing: AmenConnectMarketplaceListing
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AmenConnectCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(listing.title)
                                        .font(.systemScaled(22, weight: .black))
                                    Text("\(listing.category.rawValue) · \(listing.locationLabel)")
                                        .font(.systemScaled(13))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(listing.compensation)
                                    .font(.systemScaled(15, weight: .bold))
                            }
                            Text("Posted by \(listing.posterName) · \(listing.verificationLevel)")
                                .font(.systemScaled(13))
                                .foregroundStyle(.secondary)
                            Text("Expires \(listing.expiresLabel)")
                                .font(.systemScaled(12))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    AmenConnectCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Trust & Safety", systemImage: "checkmark.shield")
                                .font(.systemScaled(15, weight: .bold))
                            AmenConnectBadgeRow(badges: listing.trustBadges)
                            Text("Safety status: \(listing.safetyStatus.rawValue.capitalized)")
                                .font(.systemScaled(12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .navigationTitle("Listing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

struct AmenConnectCreatorDetailSheet: View {
    let creator: AmenConnectCreatorProfile
    @Environment(\.dismiss) private var dismiss
    @State private var showUserProfile = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AmenConnectCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 14) {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(LinearGradient(colors: [Color.blue.opacity(0.25), Color.green.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 64, height: 64)
                                    .overlay(Image(systemName: "person.crop.rectangle.stack").font(.system(size: 24)).foregroundStyle(.primary))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(creator.displayName)
                                        .font(.systemScaled(20, weight: .black))
                                    Text(creator.type.rawValue.capitalized)
                                        .font(.systemScaled(13, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(creator.bio)
                                .font(.systemScaled(14))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 12) {
                                Label("\(creator.memberCount) members", systemImage: "person.2")
                                Text(creator.isPaidEnabled ? "Free + paid tiers" : "Free")
                            }
                            .font(.systemScaled(12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            AmenConnectBadgeRow(badges: creator.trustBadges)
                        }
                    }
                    Button {
                        showUserProfile = true
                    } label: {
                        AmenConnectCard {
                            HStack {
                                Label("View full profile", systemImage: "person.circle")
                                    .font(.systemScaled(15, weight: .semibold))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .navigationTitle(creator.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showUserProfile) {
                UserProfileView(userId: creator.id, showsDismissButton: true)
            }
        }
    }
}

struct AmenConnectTierDetailSheet: View {
    let tier: AmenConnectMembershipTier
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AmenConnectCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(tier.name)
                                    .font(.systemScaled(22, weight: .black))
                                Spacer()
                                Text(tier.priceLabel)
                                    .font(.systemScaled(17, weight: .bold))
                                    .foregroundStyle(AmenTheme.Colors.amenGold)
                            }
                            Text("Benefits")
                                .font(.systemScaled(14, weight: .bold))
                            ForEach(tier.benefits, id: \.self) { benefit in
                                Label(benefit, systemImage: "checkmark.circle.fill")
                                    .font(.systemScaled(13))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if !tier.accessRules.isEmpty {
                        AmenConnectCard {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Access rules")
                                    .font(.systemScaled(14, weight: .bold))
                                ForEach(tier.accessRules, id: \.self) { rule in
                                    Label(rule, systemImage: "lock.open")
                                        .font(.systemScaled(13))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if !tier.safetyFlags.isEmpty {
                        AmenConnectCard {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Safety review", systemImage: "exclamationmark.shield")
                                    .font(.systemScaled(14, weight: .bold))
                                    .foregroundStyle(.orange)
                                ForEach(tier.safetyFlags, id: \.self) { flag in
                                    Text(flag)
                                        .font(.systemScaled(12))
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .navigationTitle("Membership Tier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

struct AMENConnectView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { AMENConnectView() }
    }
}
