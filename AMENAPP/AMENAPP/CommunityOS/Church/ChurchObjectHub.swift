// ChurchObjectHub.swift
// AMEN Community OS — Church OS (A8)
//
// Unified hub that links a church to all its child objects:
//   - Active Sermons/Media (horizontal scroll of media cards)
//   - Upcoming Events (horizontal scroll)
//   - Discussion Rooms (vertical list)
//   - Prayer Requests (vertical list)
//   - Volunteer Teams (horizontal scroll)
//   - Church Notes (vertical list)
//
// Feature-gated by communityOSChurchOSEnabled (default false).
//
// Design rules (C3):
//   - Page background: Color(uiColor: .systemGroupedBackground)
//   - Cards: white bg + shadow(color: .black.opacity(0.07), radius: 24, x:0, y:5) + cornerRadius(28, style:.continuous)
//   - Interactive accent: Color.accentColor only
//   - No amenGold / amenPurple / hex colors

import SwiftUI
import FirebaseFirestore

// MARK: - ChurchObjectHub

struct ChurchObjectHub: View {

    let churchId: String
    let churchName: String

    // MARK: Feature flag

    @AppStorage("community_os_church_os_enabled")
    private var featureEnabled: Bool = false

    // MARK: State

    @State private var sermons: [ChurchHubSermon] = []
    @State private var events: [ChurchHubEvent] = []
    @State private var discussionRooms: [ChurchHubDiscussionRoom] = []
    @State private var prayerRequests: [ChurchHubPrayerItem] = []
    @State private var volunteerTeams: [ChurchHubTeam] = []
    @State private var churchNotes: [ChurchHubNotePreview] = []

    @State private var isLoading = false
    @State private var loadError: String?

    // MARK: Body

    var body: some View {
        if featureEnabled {
            VStack(spacing: 0) {
                hubHeader
                hubContent
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .task { await loadData() }
        }
    }

    // MARK: Hub Header

    private var hubHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Church Hub")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .label))
                Text(churchName)
                    .font(.subheadline)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    // MARK: Hub Content

    @ViewBuilder
    private var hubContent: some View {
        if isLoading {
            loadingView
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    if !sermons.isEmpty {
                        sermonsSection
                    }
                    if !events.isEmpty {
                        eventsSection
                    }
                    if !discussionRooms.isEmpty {
                        discussionRoomsSection
                    }
                    if !prayerRequests.isEmpty {
                        prayerRequestsSection
                    }
                    if !volunteerTeams.isEmpty {
                        volunteerTeamsSection
                    }
                    if !churchNotes.isEmpty {
                        churchNotesSection
                    }
                    if allEmpty {
                        emptyState
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
    }

    private var allEmpty: Bool {
        sermons.isEmpty && events.isEmpty && discussionRooms.isEmpty &&
        prayerRequests.isEmpty && volunteerTeams.isEmpty && churchNotes.isEmpty
    }

    // MARK: Loading

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text("Loading church hub...")
                .font(.subheadline)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .accessibilityHidden(true)
    }

    // MARK: Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "building.columns")
                .font(.systemScaled(40))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
            Text("No content yet")
                .font(.headline)
                .foregroundStyle(Color(uiColor: .label))
            Text("Sermons, events, and more will appear here when available.")
                .font(.subheadline)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No church content available yet")
    }

    // MARK: - Sermons Section

    private var sermonsSection: some View {
        hubSection(title: "Sermons & Media", seeAllAction: nil) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(sermons) { sermon in
                        ChurchHubSermonCard(sermon: sermon)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Events Section

    private var eventsSection: some View {
        hubSection(title: "Upcoming Events", seeAllAction: nil) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(events) { event in
                        ChurchHubEventCard(event: event)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Discussion Rooms Section

    private var discussionRoomsSection: some View {
        hubSection(title: "Discussion Rooms", seeAllAction: nil) {
            VStack(spacing: 10) {
                ForEach(discussionRooms.prefix(3)) { room in
                    DiscussionRoomRow(room: room)
                }
            }
        }
    }

    // MARK: - Prayer Requests Section

    private var prayerRequestsSection: some View {
        hubSection(title: "Prayer Requests", seeAllAction: nil) {
            VStack(spacing: 10) {
                ForEach(prayerRequests.prefix(3)) { item in
                    PrayerRequestRow(item: item)
                }
            }
        }
    }

    // MARK: - Volunteer Teams Section

    private var volunteerTeamsSection: some View {
        hubSection(title: "Volunteer Teams", seeAllAction: nil) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(volunteerTeams) { team in
                        VolunteerTeamCard(team: team)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Church Notes Section

    private var churchNotesSection: some View {
        hubSection(title: "Church Notes", seeAllAction: nil) {
            VStack(spacing: 10) {
                ForEach(churchNotes.prefix(3)) { note in
                    ChurchNoteRow(note: note)
                }
            }
        }
    }

    // MARK: - Section Container

    private func hubSection<Content: View>(
        title: String,
        seeAllAction: (() -> Void)?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .label))
                Spacer()
                if let action = seeAllAction {
                    Button("See All", action: action)
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel("See all \(title)")
                }
            }
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.07), radius: 24, x: 0, y: 5)
        )
    }

    // MARK: - Data Loading

    private func loadData() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let db = Firestore.firestore()

        // Load in parallel — each slice is independent
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await loadSermons(db: db) }
            group.addTask { await loadEvents(db: db) }
            group.addTask { await loadDiscussionRooms(db: db) }
            group.addTask { await loadPrayerRequests(db: db) }
            group.addTask { await loadVolunteerTeams(db: db) }
            group.addTask { await loadChurchNotes(db: db) }
        }
    }

    private func loadSermons(db: Firestore) async {
        do {
            let snapshot = try await db
                .collection("mediaObjects")
                .whereField("churchId", isEqualTo: churchId)
                .whereField("isDeleted", isEqualTo: false)
                .order(by: "createdAt", descending: true)
                .limit(to: 10)
                .getDocuments()

            let loaded = snapshot.documents.compactMap { doc -> ChurchHubSermon? in
                let d = doc.data()
                guard let title = d["title"] as? String else { return nil }
                return ChurchHubSermon(
                    id: doc.documentID,
                    title: title,
                    speakerName: d["authorDisplayName"] as? String ?? "Unknown",
                    thumbnailURL: d["thumbnailURL"] as? String,
                    durationSeconds: (d["durationSeconds"] as? Double).map { Int($0) } ?? 0
                )
            }
            await MainActor.run { sermons = loaded }
        } catch {
            // Sermons load failure is non-fatal; section simply stays hidden
        }
    }

    private func loadEvents(db: Firestore) async {
        do {
            let snapshot = try await db
                .collection("events")
                .whereField("churchId", isEqualTo: churchId)
                .whereField("isDeleted", isEqualTo: false)
                .order(by: "startAt", descending: false)
                .limit(to: 10)
                .getDocuments()

            let now = Date()
            let loaded = snapshot.documents.compactMap { doc -> ChurchHubEvent? in
                let d = doc.data()
                guard let title = d["title"] as? String,
                      let ts = (d["startAt"] as? Timestamp)?.dateValue(),
                      ts >= now else { return nil }
                return ChurchHubEvent(
                    id: doc.documentID,
                    title: title,
                    startDate: ts,
                    imageURL: d["imageURL"] as? String
                )
            }
            await MainActor.run { events = loaded }
        } catch {}
    }

    private func loadDiscussionRooms(db: Firestore) async {
        do {
            let parentId = "church_\(churchId)"
            let snapshot = try await db
                .collection("objectDiscussionRooms")
                .document(parentId)
                .collection("rooms")
                .whereField("isDeleted", isEqualTo: false)
                .order(by: "lastMessageAt", descending: true)
                .limit(to: 5)
                .getDocuments()

            let loaded = snapshot.documents.compactMap { doc -> ChurchHubDiscussionRoom? in
                let d = doc.data()
                guard let title = d["canonicalObjectTitle"] as? String else { return nil }
                return ChurchHubDiscussionRoom(
                    id: doc.documentID,
                    title: title,
                    participantCount: d["participantCount"] as? Int ?? 0,
                    lastMessage: d["lastMessage"] as? String,
                    lastMessageAt: (d["lastMessageAt"] as? Timestamp)?.dateValue()
                )
            }
            await MainActor.run { discussionRooms = loaded }
        } catch {}
    }

    private func loadPrayerRequests(db: Firestore) async {
        do {
            let snapshot = try await db
                .collection("prayers")
                .whereField("churchId", isEqualTo: churchId)
                .whereField("isDeleted", isEqualTo: false)
                .order(by: "createdAt", descending: true)
                .limit(to: 5)
                .getDocuments()

            let loaded = snapshot.documents.compactMap { doc -> ChurchHubPrayerItem? in
                let d = doc.data()
                guard let body = d["body"] as? String else { return nil }
                return ChurchHubPrayerItem(
                    id: doc.documentID,
                    body: body,
                    anonymous: (d["visibility"] as? String) == "anonymous",
                    prayedCount: d["prayedCount"] as? Int ?? 0
                )
            }
            await MainActor.run { prayerRequests = loaded }
        } catch {}
    }

    private func loadVolunteerTeams(db: Firestore) async {
        do {
            let snapshot = try await db
                .collection("teams")
                .whereField("churchId", isEqualTo: churchId)
                .whereField("isDeleted", isEqualTo: false)
                .limit(to: 8)
                .getDocuments()

            let loaded = snapshot.documents.compactMap { doc -> ChurchHubTeam? in
                let d = doc.data()
                guard let name = d["name"] as? String else { return nil }
                return ChurchHubTeam(
                    id: doc.documentID,
                    name: name,
                    description: d["description"] as? String
                )
            }
            await MainActor.run { volunteerTeams = loaded }
        } catch {}
    }

    private func loadChurchNotes(db: Firestore) async {
        // Church notes are user-owned; surface only the current user's notes for this church.
        // In a full implementation this would use FirebaseAuth.currentUser?.uid.
        // For this hub surface we load a preview stub and gate behind the feature flag.
        // Full implementation requires the user session context injected by the parent.
        await MainActor.run { churchNotes = [] }
    }
}

// MARK: - Data Models (hub-local lightweight representations)

struct ChurchHubSermon: Identifiable {
    let id: String
    let title: String
    let speakerName: String
    let thumbnailURL: String?
    let durationSeconds: Int
}

struct ChurchHubEvent: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let imageURL: String?
}

struct ChurchHubDiscussionRoom: Identifiable {
    let id: String
    let title: String
    let participantCount: Int
    let lastMessage: String?
    let lastMessageAt: Date?
}

struct ChurchHubPrayerItem: Identifiable {
    let id: String
    let body: String
    let anonymous: Bool
    let prayedCount: Int
}

struct ChurchHubTeam: Identifiable {
    let id: String
    let name: String
    let description: String?
}

struct ChurchHubNotePreview: Identifiable {
    let id: String
    let title: String
    let createdAt: Date
}

// MARK: - Card / Row Sub-views

private struct ChurchHubSermonCard: View {
    let sermon: ChurchHubSermon

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let urlStr = sermon.thumbnailURL, let url = URL(string: urlStr) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            default:
                                Color(uiColor: .secondarySystemBackground)
                                    .overlay(
                                        Image(systemName: "play.rectangle.fill")
                                            .font(.systemScaled(24))
                                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                                    )
                            }
                        }
                    } else {
                        Color(uiColor: .secondarySystemBackground)
                            .overlay(
                                Image(systemName: "play.rectangle.fill")
                                    .font(.systemScaled(24))
                                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                            )
                    }
                }
                .frame(width: 160, height: 100)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if sermon.durationSeconds > 0 {
                    Text("\(sermon.durationSeconds / 60) min")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.60)))
                        .padding(6)
                }
            }

            Text(sermon.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(uiColor: .label))
                .lineLimit(2)
                .frame(width: 160, alignment: .leading)

            Text(sermon.speakerName)
                .font(.caption2)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .lineLimit(1)
                .frame(width: 160, alignment: .leading)
        }
        .frame(width: 160)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(sermon.title) by \(sermon.speakerName)")
    }
}

private struct ChurchHubEventCard: View {
    let event: ChurchHubEvent

    private var dayString: String {
        let f = DateFormatter(); f.dateFormat = "d"; return f.string(from: event.startDate)
    }
    private var monthString: String {
        let f = DateFormatter(); f.dateFormat = "MMM"; return f.string(from: event.startDate)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let urlStr = event.imageURL, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            Color(uiColor: .secondarySystemBackground)
                        }
                    }
                } else {
                    Color(uiColor: .secondarySystemBackground)
                }
            }
            .frame(width: 150, height: 110)
            .clipped()

            // Date badge
            VStack(spacing: 0) {
                Text(dayString)
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(.white)
                Text(monthString.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.80))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.black.opacity(0.60)))
            .padding(8)

            // Bottom title gradient
            VStack {
                Spacer()
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.65)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .frame(height: 50)
                .overlay(alignment: .bottomLeading) {
                    Text(event.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 6)
                }
            }
        }
        .frame(width: 150, height: 110)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.title), \(dayString) \(monthString)")
    }
}

private struct DiscussionRoomRow: View {
    let room: ChurchHubDiscussionRoom

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.systemScaled(18))
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.10))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(room.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(uiColor: .label))
                    .lineLimit(1)
                if let last = room.lastMessage {
                    Text(last)
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .lineLimit(1)
                }
            }

            Spacer()

            Text("\(room.participantCount)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(room.title). \(room.participantCount) participants.")
    }
}

private struct PrayerRequestRow: View {
    let item: ChurchHubPrayerItem
    @State private var hasPrayed = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hands.and.sparkles")
                .font(.systemScaled(16))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.body)
                    .font(.subheadline)
                    .foregroundStyle(Color(uiColor: .label))
                    .lineLimit(2)

                HStack(spacing: 4) {
                    if item.anonymous {
                        Text("Anonymous")
                            .font(.caption)
                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    }
                    Text("· \(item.prayedCount) praying")
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
            }

            Spacer(minLength: 8)

            Button {
                withAnimation(.spring(response: 0.3)) { hasPrayed = true }
            } label: {
                Text(hasPrayed ? "Prayed" : "Pray")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(hasPrayed ? Color(uiColor: .secondaryLabel) : Color.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(hasPrayed
                                  ? Color(uiColor: .secondarySystemBackground)
                                  : Color.accentColor.opacity(0.10))
                    )
            }
            .disabled(hasPrayed)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.body). \(item.prayedCount) praying.")
    }
}

private struct VolunteerTeamCard: View {
    let team: ChurchHubTeam

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "heart.circle")
                .font(.systemScaled(28))
                .foregroundStyle(Color.accentColor)
                .frame(width: 120, alignment: .leading)

            Text(team.name)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color(uiColor: .label))
                .lineLimit(2)
                .frame(width: 120, alignment: .leading)

            if let desc = team.description {
                Text(desc)
                    .font(.caption2)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .lineLimit(2)
                    .frame(width: 120, alignment: .leading)
            }
        }
        .padding(12)
        .frame(width: 140)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
                .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 2)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(team.name) volunteer team")
    }
}

private struct ChurchNoteRow: View {
    let note: ChurchHubNotePreview

    private var dateString: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: note.createdAt)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "note.text")
                .font(.systemScaled(16))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(note.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(uiColor: .label))
                    .lineLimit(1)
                Text(dateString)
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(note.title). \(dateString)")
    }
}

// MARK: - Preview

#Preview("Church Object Hub") {
    ChurchObjectHub(churchId: "church_preview_01", churchName: "Grace Community Church")
        .onAppear {
            UserDefaults.standard.set(true, forKey: "community_os_church_os_enabled")
        }
}
