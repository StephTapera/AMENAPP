//
//  AMENConnectView.swift
//  AMENAPP
//
//  Amen Connect launches from Resources and owns its internal spatial navigation.
//

import SwiftUI

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

            AmenConnectSearchCapsule(placeholder: "Search spaces, DMs, jobs, boards, creators", text: $viewModel.searchText)
                .padding(.horizontal, 20)

            AmenConnectPriorityPanel(items: viewModel.activityItems) {
                viewModel.isShowingCatchUp = true
            }
            .padding(.horizontal, 20)

            AmenConnectSectionGrid(viewModel: viewModel)
                .padding(.horizontal, 20)
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
                        .font(.systemScaled(22, weight: .semibold))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AmenConnectRoomTitle(title: "Discover", subtitle: "Find communities, mentors, jobs, trusted local help, events, cohorts, and creators.")
            AmenConnectFilterChips(filters: filters, selected: $selectedFilter)
                .padding(.horizontal, 20)
            horizontalCreatorSection(title: "Based on your memberships")
            horizontalCreatorSection(title: "Creators for you")
            AmenConnectListingSection(title: "Jobs, babysitters, tutoring, and trusted local help", listings: viewModel.listings)
            AmenConnectSpaceSection(title: "University groups near you", spaces: viewModel.spaces)
        }
    }

    private func horizontalCreatorSection(title: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.systemScaled(18, weight: .bold))
                .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.creators) { creator in
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AmenConnectRoomTitle(title: "Amen Spaces", subtitle: "Workspaces for churches, colleges, nonprofits, local help, creators, teams, and personal communities.")
            AmenConnectSpaceSection(title: "Your spaces", spaces: viewModel.spaces)
            AmenConnectBackendContractPanel(title: "Space contracts", contracts: viewModel.backendContracts.filter { $0.functionName.contains("Space") || $0.functionName.contains("Channel") })
        }
    }
}

struct AmenConnectChannelListView: View {
    var channels: [AmenConnectChannel]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AmenConnectRoomTitle(title: "Amen Channels", subtitle: "Public, private, announcement, marketplace, meeting, study, volunteer, youth-protected, and paid-member channels.")
            VStack(spacing: 10) {
                ForEach(channels) { channel in
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
                    .padding(.horizontal, 20)
                }
            }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AmenConnectRoomTitle(title: "Amen Meetings", subtitle: "Huddles, study rooms, office hours, webinars, paid live sessions, attendance, transcripts, and recaps.")
            ForEach(meetings) { meeting in
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
                .padding(.horizontal, 20)
            }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AmenConnectRoomTitle(title: "Amen Boards", subtitle: "Notion-style dashboards, pages, resources, templates, onboarding, cohort, class, ministry, and marketplace boards.")
            ForEach(boards) { board in
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
                .padding(.horizontal, 20)
            }
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
            AmenConnectBackendContractPanel(title: "Cloud Function contracts", contracts: contracts)
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

    var body: some View {
        NavigationStack {
            List {
                Section("Amen Guide actions") {
                    ForEach(["Summarize unread messages", "Turn chat into tasks", "Create event from discussion", "Draft announcement", "Create board from prompt", "Create job listing", "Create babysitting listing", "Build safe paid tier", "Review monetized offer"], id: \.self) { action in
                        Label(action, systemImage: "sparkles")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.systemScaled(18, weight: .bold))
                .padding(.horizontal, 20)
            ForEach(listings) { listing in
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
                .padding(.horizontal, 20)
            }
        }
    }
}

private struct AmenConnectCreatorCard: View {
    var creator: AmenConnectCreatorProfile

    var body: some View {
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
}

struct AmenConnectMembershipTiersView: View {
    var tiers: [AmenConnectMembershipTier]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Memberships")
                .font(.systemScaled(18, weight: .bold))
                .padding(.horizontal, 20)
            ForEach(tiers) { tier in
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
                .padding(.horizontal, 20)
            }
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

struct AMENConnectView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { AMENConnectView() }
    }
}
