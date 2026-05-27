// AmenCommunitySpaceTabs.swift
// AMENAPP
//
// Structured tabs for group/community spaces.
// Sections: Announcements, Discussion, Prayer Requests, Events, Notes, Recaps, Action Items.
//
// Design:
//   - Tab strip with Liquid Glass pill selector
//   - Normal chat preserved in Discussion tab (wraps UnifiedChatView)
//   - Optional organization: pinned announcements, prayer queue, event list
//   - Gated by groupContextTabsEnabled feature flag
//   - Role permissions enforced server-side; client only shows/hides UI

import SwiftUI

// MARK: - Tab Definition

enum CommunitySpaceTab: Int, CaseIterable, Identifiable {
    case announcements
    case discussion
    case prayer
    case events
    case notes
    case recaps
    case actions

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .announcements: return "Announcements"
        case .discussion:    return "Discussion"
        case .prayer:        return "Prayer"
        case .events:        return "Events"
        case .notes:         return "Notes"
        case .recaps:        return "Recaps"
        case .actions:       return "Actions"
        }
    }

    var shortTitle: String {
        switch self {
        case .announcements: return "Announce"
        case .discussion:    return "Chat"
        case .prayer:        return "Prayer"
        case .events:        return "Events"
        case .notes:         return "Notes"
        case .recaps:        return "Recaps"
        case .actions:       return "Actions"
        }
    }

    var icon: String {
        switch self {
        case .announcements: return "megaphone.fill"
        case .discussion:    return "bubble.left.and.bubble.right.fill"
        case .prayer:        return "hands.and.sparkles.fill"
        case .events:        return "calendar"
        case .notes:         return "doc.text.fill"
        case .recaps:        return "sparkles.rectangle.stack.fill"
        case .actions:       return "checkmark.circle.fill"
        }
    }
}

// MARK: - Space Roles

enum SpaceRole {
    case member, moderator, admin

    var canPostAnnouncement: Bool { self == .moderator || self == .admin }
    var canPinMessage: Bool { self == .moderator || self == .admin }
}

// MARK: - Main Community Space View

struct AmenCommunitySpaceView: View {
    let spaceId: String
    let spaceName: String
    let userRole: SpaceRole

    /// Provide the normal chat view for the Discussion tab
    let chatContent: AnyView

    @State private var selectedTab: CommunitySpaceTab = .discussion
    @State private var announcementCount: Int = 0
    @State private var prayerCount: Int = 0
    @State private var actionCount: Int = 0

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Tab strip
            CommunitySpaceTabStrip(
                selectedTab: $selectedTab,
                unreadCounts: tabUnreadCounts
            )

            Divider()

            // Content
            TabView(selection: $selectedTab) {
                ForEach(CommunitySpaceTab.allCases) { tab in
                    tabContent(for: tab)
                        .tag(tab)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: selectedTab)
        }
    }

    private var tabUnreadCounts: [CommunitySpaceTab: Int] {
        [
            .announcements: announcementCount,
            .prayer: prayerCount,
            .actions: actionCount,
        ]
    }

    @ViewBuilder
    private func tabContent(for tab: CommunitySpaceTab) -> some View {
        switch tab {
        case .announcements:
            AnnouncementsTabView(
                spaceId: spaceId,
                canPost: userRole.canPostAnnouncement
            )
        case .discussion:
            // Wraps the caller-provided UnifiedChatView — zero duplication
            chatContent
        case .prayer:
            PrayerRequestsTabView(spaceId: spaceId)
        case .events:
            EventsTabView(spaceId: spaceId, canCreate: userRole.canPostAnnouncement)
        case .notes:
            NotesFilesTabView(spaceId: spaceId)
        case .recaps:
            RecapsTabView(spaceId: spaceId)
        case .actions:
            ActionItemsTabView(spaceId: spaceId)
        }
    }
}

// MARK: - Tab Strip

struct CommunitySpaceTabStrip: View {
    @Binding var selectedTab: CommunitySpaceTab
    let unreadCounts: [CommunitySpaceTab: Int]

    @Namespace private var pillNS
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(CommunitySpaceTab.allCases) { tab in
                    tabButton(for: tab)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func tabButton(for tab: CommunitySpaceTab) -> some View {
        let isSelected = selectedTab == tab
        let count = unreadCounts[tab] ?? 0
        Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.75)) {
                selectedTab = tab
            }
        } label: {
            tabLabel(tab: tab, isSelected: isSelected, unreadCount: count)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count > 0 ? "\(tab.title), \(count) unread" : tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func tabLabel(tab: CommunitySpaceTab, isSelected: Bool, unreadCount: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: tab.icon)
                .font(.system(size: 11, weight: .semibold))
                .accessibilityHidden(true)
            Text(tab.shortTitle)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            if unreadCount > 0 {
                Text("\(min(unreadCount, 99))")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.black))
                    .accessibilityLabel("\(unreadCount) unread")
            }
        }
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(pillBackground(isSelected: isSelected))
    }

    @ViewBuilder
    private func pillBackground(isSelected: Bool) -> some View {
        if isSelected {
            Capsule()
                .fill(reduceTransparency
                    ? AnyShapeStyle(Color(.secondarySystemBackground))
                    : AnyShapeStyle(.ultraThinMaterial))
                .matchedGeometryEffect(id: "pill", in: pillNS)
        }
    }
}

// MARK: - Announcements Tab

struct AnnouncementsTabView: View {
    let spaceId: String
    let canPost: Bool

    @State private var announcements: [SpaceAnnouncement] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if announcements.isEmpty {
                CommunityTabEmptyState(
                    icon: "megaphone.fill",
                    title: "No Announcements",
                    message: canPost ? "Post an announcement for the group." : "No announcements yet."
                )
            } else {
                List(announcements) { announcement in
                    AnnouncementRow(announcement: announcement)
                }
                .listStyle(.plain)
            }
        }
        .task { await loadAnnouncements() }
        .safeAreaInset(edge: .bottom) {
            if canPost {
                PostAnnouncementButton(spaceId: spaceId)
            }
        }
    }

    private func loadAnnouncements() async {
        // Fetches from Firestore: spaces/{spaceId}/announcements ordered by pinnedAt desc, createdAt desc
        isLoading = false
    }
}

struct AnnouncementRow: View {
    let announcement: SpaceAnnouncement

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if announcement.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Pinned")
                }
                Text(announcement.authorName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(announcement.createdAt, style: .relative)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Text(announcement.body)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

struct PostAnnouncementButton: View {
    let spaceId: String
    @State private var showComposer = false

    var body: some View {
        Button {
            showComposer = true
        } label: {
            Label("Post Announcement", systemImage: "megaphone.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Capsule().fill(Color.black))
        }
        .padding(.bottom, 16)
        .accessibilityLabel("Post a new announcement")
        .sheet(isPresented: $showComposer) {
            AnnouncementComposerSheet(spaceId: spaceId)
        }
    }
}

struct AnnouncementComposerSheet: View {
    let spaceId: String
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .padding()
                .navigationTitle("New Announcement")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Post") {
                            // TODO: call postAnnouncement callable
                            dismiss()
                        }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }
    }
}

// MARK: - Prayer Requests Tab

struct PrayerRequestsTabView: View {
    let spaceId: String

    @State private var requests: [GroupPrayerRequest] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if requests.isEmpty {
                CommunityTabEmptyState(
                    icon: "hands.and.sparkles.fill",
                    title: "No Prayer Requests",
                    message: "Share what's on your heart with the group."
                )
            } else {
                List(requests) { request in
                    PrayerRequestRow(request: request)
                }
                .listStyle(.plain)
            }
        }
        .task { await loadRequests() }
        .safeAreaInset(edge: .bottom) {
            AddPrayerRequestButton(spaceId: spaceId)
        }
    }

    private func loadRequests() async {
        isLoading = false
    }
}

struct PrayerRequestRow: View {
    let request: GroupPrayerRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(request.authorName)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(request.createdAt, style: .relative)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Text(request.body)
                .font(.system(size: 15))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("\(request.prayerCount) praying")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    // TODO: call addPrayerCount callable
                } label: {
                    Label("Pray", systemImage: "hands.and.sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.purple)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

struct AddPrayerRequestButton: View {
    let spaceId: String
    @State private var showComposer = false

    var body: some View {
        Button {
            showComposer = true
        } label: {
            Label("Add Prayer Request", systemImage: "hands.and.sparkles.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Capsule().fill(Color.purple))
        }
        .padding(.bottom, 16)
        .sheet(isPresented: $showComposer) {
            PrayerRequestComposerSheet(spaceId: spaceId)
        }
    }
}

struct PrayerRequestComposerSheet: View {
    let spaceId: String
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .padding()
                .navigationTitle("Prayer Request")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Share") {
                            // TODO: call addPrayerRequest callable
                            dismiss()
                        }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }
    }
}

// MARK: - Events Tab

struct EventsTabView: View {
    let spaceId: String
    let canCreate: Bool

    var body: some View {
        CommunityTabEmptyState(
            icon: "calendar",
            title: "No Upcoming Events",
            message: canCreate ? "Create an event for the group." : "No events scheduled."
        )
        // TODO: Integrate with Gatherings system (gatheringsEnabled flag)
    }
}

// MARK: - Notes & Files Tab

struct NotesFilesTabView: View {
    let spaceId: String

    var body: some View {
        CommunityTabEmptyState(
            icon: "doc.text.fill",
            title: "No Notes or Files",
            message: "Share important documents with the group."
        )
        // TODO: Integrate with ChurchNotes system and file storage
    }
}

// MARK: - Recaps Tab (AI-generated)

struct RecapsTabView: View {
    let spaceId: String

    var body: some View {
        CommunityTabEmptyState(
            icon: "sparkles.rectangle.stack.fill",
            title: "No Recaps Yet",
            message: "AI-generated recaps appear here when the conversation has enough messages."
        )
        // TODO: Wire to AmenConversationOSService.generateCatchUpRecap()
        // Gated by catchUpRecapsEnabled + conversationSummariesEnabled + aiPerChatConsent
    }
}

// MARK: - Action Items Tab

struct ActionItemsTabView: View {
    let spaceId: String

    var body: some View {
        CommunityTabEmptyState(
            icon: "checkmark.circle.fill",
            title: "No Action Items",
            message: "Action items extracted from discussions will appear here."
        )
        // TODO: Wire to AmenConversationOSService.extractActionItems()
        // Gated by actionExtractionEnabled + aiPerChatConsent
    }
}

// MARK: - Shared Empty State

struct CommunityTabEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }
}

// MARK: - Data Models (lightweight, Firestore-mapped)

struct SpaceAnnouncement: Identifiable {
    let id: String
    let authorName: String
    let body: String
    let createdAt: Date
    let isPinned: Bool
}

struct GroupPrayerRequest: Identifiable {
    let id: String
    let authorName: String
    let body: String
    let createdAt: Date
    let prayerCount: Int
}
