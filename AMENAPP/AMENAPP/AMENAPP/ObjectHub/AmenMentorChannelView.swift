import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Mentor Channel Models

struct MentorChannelProfile: Identifiable {
    let id: String
    let displayName: String
    let tagline: String?
    let avatarURL: String?
    let coverVideoURL: String?     // intro-video hero
    let churchAffiliation: String?
    let ministeringFocus: [String]
    let officeHoursAvailable: Bool
    let mentorshipOpenings: Int
    let followerCount: Int
    let teachingCount: Int
    let activeSince: Date?
}

struct MentorTeachingItem: Identifiable {
    let id: String
    let title: String
    let seriesName: String?
    let thumbnailURL: String?
    let durationLabel: String?
    let postedAt: Date?
}

struct MentorEventItem: Identifiable {
    let id: String
    let title: String
    let dateLabel: String
    let locationLabel: String?
    let isOnline: Bool
}

// MARK: - Mentor Channel ViewModel

@MainActor
final class AmenMentorChannelViewModel: ObservableObject {
    @Published var profile: MentorChannelProfile?
    @Published var recentTeachings: [MentorTeachingItem] = []
    @Published var currentSeries: [MentorTeachingItem] = []
    @Published var upcomingEvents: [MentorEventItem] = []
    @Published var prayerRequestCount: Int = 0
    @Published var affordances: [ObjectAffordance] = []
    @Published var isLoading = false
    @Published var error: String?

    private let db = Firestore.firestore()

    func load(mentorId: String) async {
        isLoading = true
        defer { isLoading = false }

        async let profileTask = fetchProfile(mentorId: mentorId)
        async let teachingsTask = fetchRecentTeachings(mentorId: mentorId)
        async let eventsTask = fetchUpcomingEvents(mentorId: mentorId)
        async let affordancesTask = AmenObjectDiscussionService.shared.buildAffordances(
            objectId:    "mentor-\(mentorId)",
            objectTitle: "Mentor Channel"
        )

        let (p, t, e, a) = await (profileTask, teachingsTask, eventsTask, affordancesTask)
        profile = p
        recentTeachings = t
        upcomingEvents = e
        affordances = a

        if let p {
            let seriesTeachings = t.filter { $0.seriesName != nil }
            currentSeries = Array(seriesTeachings.prefix(6))
            // Update affordance label with real display name
            affordances = await AmenObjectDiscussionService.shared.buildAffordances(
                objectId:    "mentor-\(mentorId)",
                objectTitle: p.displayName
            )
        }
    }

    private func fetchProfile(mentorId: String) async -> MentorChannelProfile? {
        guard let doc = try? await db.collection("users").document(mentorId).getDocument(),
              doc.exists,
              let data = doc.data() else { return nil }

        let name = data["displayName"] as? String ?? "Mentor"
        return MentorChannelProfile(
            id: mentorId,
            displayName: name,
            tagline: data["tagline"] as? String,
            avatarURL: data["photoURL"] as? String,
            coverVideoURL: data["coverVideoURL"] as? String,
            churchAffiliation: data["churchName"] as? String,
            ministeringFocus: data["ministeringFocus"] as? [String] ?? [],
            officeHoursAvailable: data["officeHoursEnabled"] as? Bool ?? false,
            mentorshipOpenings: data["mentorshipOpenings"] as? Int ?? 0,
            followerCount: data["followerCount"] as? Int ?? 0,
            teachingCount: data["teachingCount"] as? Int ?? 0,
            activeSince: (data["createdAt"] as? Timestamp)?.dateValue()
        )
    }

    private func fetchRecentTeachings(mentorId: String) async -> [MentorTeachingItem] {
        guard let snap = try? await db.collection("posts")
            .whereField("userId", isEqualTo: mentorId)
            .whereField("type", isEqualTo: "teaching")
            .order(by: "createdAt", descending: true)
            .limit(to: 10)
            .getDocuments() else { return [] }

        return snap.documents.compactMap { doc -> MentorTeachingItem? in
            let d = doc.data()
            guard let title = d["title"] as? String ?? d["body"] as? String else { return nil }
            return MentorTeachingItem(
                id: doc.documentID,
                title: title,
                seriesName: d["seriesName"] as? String,
                thumbnailURL: d["thumbnailURL"] as? String,
                durationLabel: d["durationLabel"] as? String,
                postedAt: (d["createdAt"] as? Timestamp)?.dateValue()
            )
        }
    }

    private func fetchUpcomingEvents(mentorId: String) async -> [MentorEventItem] {
        guard let snap = try? await db.collection("events")
            .whereField("hostId", isEqualTo: mentorId)
            .whereField("startAt", isGreaterThan: Timestamp(date: Date()))
            .order(by: "startAt")
            .limit(to: 5)
            .getDocuments() else { return [] }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        return snap.documents.compactMap { doc -> MentorEventItem? in
            let d = doc.data()
            guard let title = d["title"] as? String else { return nil }
            let date = (d["startAt"] as? Timestamp)?.dateValue()
            let dateLabel = date.map { formatter.string(from: $0) } ?? "TBD"
            return MentorEventItem(
                id: doc.documentID,
                title: title,
                dateLabel: dateLabel,
                locationLabel: d["location"] as? String,
                isOnline: d["isOnline"] as? Bool ?? false
            )
        }
    }
}

// MARK: - Mentor Channel View

/// A6: The Mentor Channel surface — a living, relationship-first channel view.
/// Hero: avatar + cover video (collapses on scroll).
/// Rails: Recent Teachings · Current Series · Active Discussions · Upcoming Events ·
///        Prayer Requests · Office Hours · Mentorship Openings.
/// Above the fold: relationship affordances (Discussion · Prayer Room · Study Group).
struct AmenMentorChannelView: View {
    let mentorId: String

    @StateObject private var vm = AmenMentorChannelViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var activeRoomType: ObjectDiscussionRoom.ObjectDiscussionRoomType = .discussion
    @State private var showDiscussionRoom = false
    @State private var heroCollapsed = false
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            if vm.isLoading {
                loadingState
            } else if let profile = vm.profile {
                channelContent(profile: profile)
            } else {
                emptyState
            }

            floatingNav
        }
        .ignoresSafeArea(edges: .top)
        .task { await vm.load(mentorId: mentorId) }
        .sheet(isPresented: $showDiscussionRoom) {
            if let profile = vm.profile {
                AmenObjectDiscussionRoomView(
                    objectId:     "mentor-\(mentorId)",
                    objectTitle:  profile.displayName,
                    roomType:     activeRoomType,
                    existingRoom: nil
                )
            }
        }
    }

    // MARK: - Channel Content

    private func channelContent(profile: MentorChannelProfile) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Hero — collapses on scroll
                mentorHero(profile: profile)

                VStack(spacing: 28) {
                    // Affordance chips — above the fold, relationship-first
                    if !vm.affordances.isEmpty {
                        AmenAffordanceChipRow(affordances: vm.affordances) { affordance in
                            handleAffordanceTap(affordance)
                        }
                    }

                    // Mentor stats bar
                    mentorStatsBar(profile: profile)
                        .padding(.horizontal, 16)

                    // Rail: Recent Teachings
                    if !vm.recentTeachings.isEmpty {
                        channelRail(
                            title: "Recent Teachings",
                            icon: "play.rectangle.fill"
                        ) {
                            ForEach(vm.recentTeachings) { item in
                                TeachingCard(item: item)
                            }
                        }
                    }

                    // Rail: Current Series
                    if !vm.currentSeries.isEmpty {
                        channelRail(
                            title: "Current Series",
                            icon: "books.vertical.fill"
                        ) {
                            ForEach(vm.currentSeries) { item in
                                TeachingCard(item: item)
                            }
                        }
                    }

                    // Rail: Upcoming Events
                    if !vm.upcomingEvents.isEmpty {
                        channelRail(
                            title: "Upcoming Events",
                            icon: "calendar"
                        ) {
                            ForEach(vm.upcomingEvents) { event in
                                MentorEventCard(event: event)
                            }
                        }
                    }

                    // Office Hours CTA
                    if profile.officeHoursAvailable {
                        officeHoursCTA(profile: profile)
                            .padding(.horizontal, 16)
                    }

                    // Mentorship Openings CTA
                    if profile.mentorshipOpenings > 0 {
                        mentorshipOpeningsCTA(profile: profile)
                            .padding(.horizontal, 16)
                    }

                    // Focus tags
                    if !profile.ministeringFocus.isEmpty {
                        focusTags(profile.ministeringFocus)
                            .padding(.horizontal, 16)
                    }

                    Spacer(minLength: 48)
                }
                .padding(.top, 20)
            }
        }
    }

    // MARK: - Hero

    private func mentorHero(profile: MentorChannelProfile) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Cover — gradient fallback if no video
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.purple.opacity(0.7), Color.indigo.opacity(0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: heroCollapsed ? 120 : 280)
                .animation(reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.8), value: heroCollapsed)

            // Identity
            HStack(alignment: .bottom, spacing: 14) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 72, height: 72)

                    if let avatarURL = profile.avatarURL,
                       let url = URL(string: avatarURL) {
                        AsyncImage(url: url) { phase in
                            if case .success(let img) = phase {
                                img.resizable().scaledToFill()
                            } else {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 72, height: 72)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white)
                    }
                }
                .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 1.5))

                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.displayName)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    if let tagline = profile.tagline {
                        Text(tagline)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                    if let church = profile.churchAffiliation {
                        Text(church)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Stats Bar

    private func mentorStatsBar(profile: MentorChannelProfile) -> some View {
        HStack(spacing: 0) {
            statItem(value: formatCount(profile.followerCount), label: "Followers")
            Divider().frame(height: 32)
            statItem(value: "\(profile.teachingCount)", label: "Teachings")
            Divider().frame(height: 32)
            statItem(
                value: profile.officeHoursAvailable ? "Open" : "Closed",
                label: "Office Hours"
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(reduceTransparency ? AnyShapeStyle(Color(.systemGray6)) : AnyShapeStyle(.thinMaterial))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
        )
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Rails

    private func channelRail<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text("See all")
                    .font(.subheadline)
                    .foregroundStyle(.purple)
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    content()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
            }
        }
    }

    // MARK: - Office Hours CTA

    private func officeHoursCTA(profile: MentorChannelProfile) -> some View {
        Button {
            activeRoomType = .discussion
            showDiscussionRoom = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.green.opacity(0.15)).frame(width: 44, height: 44)
                    Image(systemName: "clock.badge.checkmark.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.green)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Office Hours Open")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Start a conversation with \(profile.displayName.components(separatedBy: " ").first ?? "them")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(reduceTransparency ? AnyShapeStyle(Color(.systemGray6)) : AnyShapeStyle(.ultraThinMaterial))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.green.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Office hours open. Start a conversation with \(profile.displayName).")
    }

    // MARK: - Mentorship Openings CTA

    private func mentorshipOpeningsCTA(profile: MentorChannelProfile) -> some View {
        Button {
            activeRoomType = .studyGroup
            showDiscussionRoom = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.purple.opacity(0.15)).frame(width: 44, height: 44)
                    Image(systemName: "person.badge.plus.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.purple)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(profile.mentorshipOpenings) Mentorship \(profile.mentorshipOpenings == 1 ? "Opening" : "Openings")")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Request a mentorship with \(profile.displayName.components(separatedBy: " ").first ?? "them")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(reduceTransparency ? AnyShapeStyle(Color(.systemGray6)) : AnyShapeStyle(.ultraThinMaterial))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(profile.mentorshipOpenings) mentorship openings. Request a mentorship with \(profile.displayName).")
    }

    // MARK: - Focus Tags

    private func focusTags(_ tags: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ministering Focus")
                .font(.headline)
                .foregroundStyle(.primary)

            MentorFlowLayout(tags) { tag in
                Text(tag)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.purple.opacity(0.1))
                    )
            }
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
            Text("Loading channel…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "person.slash")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("Channel not found.")
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - Floating Nav

    private var floatingNav: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background {
                        if reduceTransparency {
                            Circle().fill(Color.black.opacity(0.6))
                        } else {
                            Circle().fill(.ultraThinMaterial)
                        }
                    }
                    .clipShape(Circle())
            }
            .accessibilityLabel("Back")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 56)
    }

    // MARK: - Helpers

    private func handleAffordanceTap(_ affordance: ObjectAffordance) {
        switch affordance.kind {
        case .discussion:     activeRoomType = .discussion
        case .prayerRoom:     activeRoomType = .prayer
        case .studyGroup:     activeRoomType = .studyGroup
        case .membersPresent, .liveNow: activeRoomType = .discussion
        }
        showDiscussionRoom = true
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 1_000_000 { return "\(n / 1_000_000)M" }
        if n >= 1_000 { return "\(n / 1_000)k" }
        return "\(n)"
    }
}

// MARK: - Teaching Card

private struct TeachingCard: View {
    let item: MentorTeachingItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.purple.opacity(0.1))
                    .frame(width: 160, height: 100)

                if let thumbnailURL = item.thumbnailURL,
                   let url = URL(string: thumbnailURL) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                        } else {
                            Image(systemName: "play.rectangle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.purple.opacity(0.4))
                        }
                    }
                    .frame(width: 160, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.purple.opacity(0.4))
                }

                if let duration = item.durationLabel {
                    Text(duration)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.6)))
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            .frame(width: 160, height: 100)

            Text(item.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(width: 160, alignment: .leading)

            if let series = item.seriesName {
                Text(series)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 160, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.title + (item.seriesName.map { " — \($0)" } ?? ""))
    }
}

// MARK: - Event Card

private struct MentorEventCard: View {
    let event: MentorEventItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.2), Color.red.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 180, height: 80)

                VStack(spacing: 4) {
                    Image(systemName: event.isOnline ? "video.fill" : "mappin.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.orange)
                    Text(event.isOnline ? "Online" : "In Person")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            .frame(width: 180, height: 80)

            Text(event.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(width: 180, alignment: .leading)

            Text(event.dateLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 180, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.title), \(event.dateLabel), \(event.isOnline ? "online" : event.locationLabel ?? "in person")")
    }
}

// MARK: - Flow Layout (wrapping tag row)

private struct MentorFlowLayout<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let data: Data
    let content: (Data.Element) -> Content

    init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.content = content
    }

    var body: some View {
        var width: CGFloat = 0
        var height: CGFloat = 0
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(Array(data.enumerated()), id: \.element) { _, item in
                    content(item)
                        .alignmentGuide(.leading) { d in
                            if abs(width - d.width) > geo.size.width {
                                width = 0; height -= d.height + 6
                            }
                            let result = width
                            if item == data.last { width = 0 } else { width -= d.width + 8 }
                            return result
                        }
                        .alignmentGuide(.top) { _ in
                            let result = height
                            if item == data.last { height = 0 }
                            return result
                        }
                }
            }
        }
        .frame(height: 80)
    }
}
