// SpaceDashboardView.swift
// AMENAPP — SpacesOS
// Smart Space Dashboard with collapsible sections and role-aware actions.

import SwiftUI

struct SpaceDashboardView: View {
    let spaceId: String
    let spaceName: String
    let memberRole: SpaceMemberRole
    let dashboardData: SpaceDashboardData

    @State private var showComposer = false
    @State private var composerType: SpacePostType = .discussion
    @State private var expandedSections: Set<DashboardSection> = [.announcements, .prayerRequests, .upcomingEvents]

    enum DashboardSection: String, CaseIterable {
        case announcements, prayerRequests, upcomingEvents, birthdays, volunteerNeeds, recentNotes

        var title: String {
            switch self {
            case .announcements:   return "Announcements"
            case .prayerRequests:  return "Prayer Requests"
            case .upcomingEvents:  return "Upcoming Events"
            case .birthdays:       return "Birthdays This Week"
            case .volunteerNeeds:  return "Volunteer Needs"
            case .recentNotes:     return "Recent Notes"
            }
        }

        var icon: String {
            switch self {
            case .announcements:  return "megaphone.fill"
            case .prayerRequests: return "hands.sparkles.fill"
            case .upcomingEvents: return "calendar"
            case .birthdays:      return "gift.fill"
            case .volunteerNeeds: return "person.badge.plus.fill"
            case .recentNotes:    return "note.text"
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                LazyVStack(spacing: 12) {
                    // Announcements
                    if !dashboardData.announcements.isEmpty {
                        dashboardSection(.announcements) {
                            ForEach(dashboardData.announcements) { item in
                                AnnouncementRow(announcement: item)
                            }
                        }
                    }

                    // Prayer Requests
                    if !dashboardData.prayerRequests.isEmpty {
                        dashboardSection(.prayerRequests) {
                            ForEach(dashboardData.prayerRequests) { item in
                                PrayerRequestRow(request: item)
                            }
                        }
                    }

                    // Upcoming Events
                    if !dashboardData.upcomingEvents.isEmpty {
                        dashboardSection(.upcomingEvents) {
                            ForEach(dashboardData.upcomingEvents.prefix(3)) { item in
                                EventRow(event: item)
                            }
                        }
                    }

                    // Birthdays
                    if !dashboardData.birthdaysThisWeek.isEmpty {
                        dashboardSection(.birthdays) {
                            ForEach(dashboardData.birthdaysThisWeek) { item in
                                BirthdayRow(birthday: item)
                            }
                        }
                    }

                    // Volunteer Needs
                    if !dashboardData.volunteerNeeds.isEmpty {
                        dashboardSection(.volunteerNeeds) {
                            ForEach(dashboardData.volunteerNeeds) { item in
                                VolunteerNeedRow(need: item)
                            }
                        }
                    }

                    // Recent Notes
                    if !dashboardData.recentNotes.isEmpty {
                        dashboardSection(.recentNotes) {
                            ForEach(dashboardData.recentNotes.prefix(3)) { item in
                                NoteRow(note: item)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 100)
            }

            // Role-aware action bar
            SpaceRoleActionBar(
                role: memberRole,
                spaceName: spaceName,
                onPost: { presentComposer(.discussion) },
                onAnnouncement: { presentComposer(.announcement) },
                onEvent: { presentComposer(.event) },
                onPrayer: { presentComposer(.prayerRoom) },
                onMembers: {},
                onAnalytics: {}
            )
        }
        .navigationTitle(spaceName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showComposer) {
            SpaceSmartComposer(
                spaceName: spaceName,
                memberRole: memberRole,
                onSubmit: { _, _ in },
                onDismiss: { showComposer = false }
            )
            .presentationDetents([.large])
        }
    }

    // MARK: - Section Builder

    @ViewBuilder
    private func dashboardSection<Content: View>(
        _ section: DashboardSection,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isExpanded = expandedSections.contains(section)
        VStack(spacing: 0) {
            // Section header
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    if isExpanded { expandedSections.remove(section) }
                    else { expandedSections.insert(section) }
                }
            } label: {
                HStack {
                    Label(section.title, systemImage: section.icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(section.title)
            .accessibilityHint(isExpanded ? "Collapse section" : "Expand section")

            if isExpanded {
                Divider().opacity(0.3).padding(.horizontal, 14)
                VStack(spacing: 0) {
                    content()
                }
                .padding(.bottom, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func presentComposer(_ type: SpacePostType) {
        composerType = type
        showComposer = true
    }
}

// MARK: - Section Rows

private struct AnnouncementRow: View {
    let announcement: SpaceAnnouncement
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if announcement.isPinned {
                Image(systemName: "pin.fill").font(.caption).foregroundStyle(Color.accentColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(announcement.title).font(.subheadline.weight(.semibold))
                Text(announcement.body).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Text(announcement.authorName).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

private struct PrayerRequestRow: View {
    let request: SpacePrayerRequest
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hands.sparkles.fill").font(.subheadline).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(request.body).font(.subheadline).lineLimit(3)
                HStack {
                    Text(request.displayName).font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                    Label("\(request.prayerCount)", systemImage: "hands.sparkles")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

private struct EventRow: View {
    let event: SpaceEvent
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title).font(.subheadline.weight(.semibold))
                Text(event.date, style: .date).font(.caption).foregroundStyle(.secondary)
                if let loc = event.location { Text(loc).font(.caption2).foregroundStyle(.tertiary) }
            }
            Spacer()
            Button {
            } label: {
                Text(event.hasRsvped ? "Going ✓" : "RSVP")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .foregroundStyle(event.hasRsvped ? Color.accentColor : .white)
                    .background(event.hasRsvped ? Color.accentColor.opacity(0.15) : Color.accentColor, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

private struct BirthdayRow: View {
    let birthday: SpaceBirthday
    var body: some View {
        HStack {
            Image(systemName: "gift.fill").foregroundStyle(Color.pink)
            Text(birthday.memberName).font(.subheadline)
            Spacer()
            Text(birthday.date, style: .date).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

private struct VolunteerNeedRow: View {
    let need: SpaceVolunteerNeed
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(need.role).font(.subheadline.weight(.semibold))
                Text(need.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Button {} label: {
                Text("Help")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .foregroundStyle(.white)
                    .background(Color.accentColor, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

private struct NoteRow: View {
    let note: SpaceNote
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "note.text").foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(note.title).font(.subheadline.weight(.semibold))
                Text(note.snippet).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Text(note.authorName).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SpaceDashboardView(
            spaceId: "space-1",
            spaceName: "Sunday Morning Group",
            memberRole: .member,
            dashboardData: .preview
        )
    }
}
