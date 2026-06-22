import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Channel-specific data models

struct MentorChannelProfile: Identifiable {
    let id: String
    let displayName: String
    let tagline: String?
    let avatarURL: String?
    let heroImageURL: String?
    let churchAffiliation: String?
    let ministeringFocus: [String]
    let bio: String?
    let officeHoursAvailable: Bool
    let mentorshipOpenings: Int
    let followerCount: Int
    let teachingCount: Int
    let discussionCount: Int
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

struct MentorOfficeHourSlot: Identifiable {
    let id: String
    let startTime: Date
    let endTime: Date
    let isBooked: Bool
}

struct MentorActiveDiscussion: Identifiable {
    let id: String
    let title: String
    let participantCount: Int
    let lastActiveAt: Date?
}

struct MentorEventItem: Identifiable {
    let id: String
    let title: String
    let startAt: Date?
    let locationLabel: String?
    let isOnline: Bool
    let rsvpCount: Int
}

struct MentorStudySeries: Identifiable {
    let id: String
    let title: String
    let lessonCount: Int
    let isEnrolled: Bool
    let progressFraction: Double
}

struct RelatedMentorItem: Identifiable {
    let id: String
    let displayName: String
    let avatarURL: String?
    let primarySpecialty: String?
}

// MARK: - View Model

@MainActor
final class AmenMentorChannelViewModel: ObservableObject {
    @Published var profile: MentorChannelProfile?
    @Published var recentTeachings: [MentorTeachingItem] = []
    @Published var officeHourSlots: [MentorOfficeHourSlot] = []
    @Published var activeDiscussions: [MentorActiveDiscussion] = []
    @Published var upcomingEvents: [MentorEventItem] = []
    @Published var studySeries: [MentorStudySeries] = []
    @Published var relatedMentors: [RelatedMentorItem] = []
    @Published var affordances: [ObjectAffordance] = []
    @Published var isFollowing = false
    @Published var isLoading = false
    @Published var error: String?

    // Per-rail loading flags
    @Published var isLoadingTeachings = true
    @Published var isLoadingOfficeHours = true
    @Published var isLoadingDiscussions = true
    @Published var isLoadingEvents = true
    @Published var isLoadingStudies = true
    @Published var isLoadingRelated = true

    private let db = Firestore.firestore()

    func load(mentorId: String) async {
        isLoading = true
        defer { isLoading = false }

        // Hero profile loads first — unblocks render immediately
        profile = await fetchProfile(mentorId: mentorId)

        guard let p = profile else { return }

        affordances = await AmenObjectDiscussionService.shared.buildAffordances(
            objectId:    "mentor-\(mentorId)",
            objectTitle: p.displayName
        )

        // Rails load concurrently in background
        async let t  = fetchRecentTeachings(mentorId: mentorId)
        async let oh = fetchOfficeHours(mentorId: mentorId)
        async let d  = fetchActiveDiscussions(mentorId: mentorId)
        async let ev = fetchUpcomingEvents(mentorId: mentorId)
        async let ss = fetchStudySeries(mentorId: mentorId)
        async let rm = fetchRelatedMentors(specialties: p.ministeringFocus)

        recentTeachings   = await t;  isLoadingTeachings   = false
        officeHourSlots   = await oh; isLoadingOfficeHours = false
        activeDiscussions = await d;  isLoadingDiscussions = false
        upcomingEvents    = await ev; isLoadingEvents      = false
        studySeries       = await ss; isLoadingStudies     = false
        relatedMentors    = await rm; isLoadingRelated     = false
    }

    func toggleFollow(mentorId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isFollowing.toggle()
        let ref = db.collection("users").document(uid)
            .collection("following").document(mentorId)
        if isFollowing {
            try? await ref.setData(["followedAt": FieldValue.serverTimestamp()])
        } else {
            try? await ref.delete()
        }
    }

    func submitMentorshipRequest(mentorId: String, goal: String, availability: String, message: String) async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        let data: [String: Any] = [
            "mentorId":      mentorId,
            "menteeId":      uid,
            "goal":          goal,
            "availability":  availability,
            "message":       message,
            "status":        "pending",
            "createdAt":     FieldValue.serverTimestamp()
        ]
        do {
            try await db.collection("mentorshipRequests")
                .document(mentorId)
                .collection("requests")
                .addDocument(data: data)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Firestore fetchers

    private func fetchProfile(mentorId: String) async -> MentorChannelProfile? {
        guard let doc = try? await db.collection("users").document(mentorId).getDocument(),
              doc.exists,
              let data = doc.data() else { return nil }

        let followingSnap = try? await db.collection("users")
            .document(Auth.auth().currentUser?.uid ?? "")
            .collection("following")
            .document(mentorId)
            .getDocument()
        isFollowing = followingSnap?.exists ?? false

        return MentorChannelProfile(
            id:                  mentorId,
            displayName:         data["displayName"] as? String ?? "Mentor",
            tagline:             data["tagline"] as? String,
            avatarURL:           data["photoURL"] as? String,
            heroImageURL:        data["heroImageURL"] as? String ?? data["photoURL"] as? String,
            churchAffiliation:   data["churchName"] as? String,
            ministeringFocus:    data["ministeringFocus"] as? [String] ?? [],
            bio:                 data["bio"] as? String,
            officeHoursAvailable: data["officeHoursEnabled"] as? Bool ?? false,
            mentorshipOpenings:  data["mentorshipOpenings"] as? Int ?? 0,
            followerCount:       data["followerCount"] as? Int ?? 0,
            teachingCount:       data["teachingCount"] as? Int ?? 0,
            discussionCount:     data["discussionCount"] as? Int ?? 0,
            activeSince:         (data["createdAt"] as? Timestamp)?.dateValue()
        )
    }

    private func fetchRecentTeachings(mentorId: String) async -> [MentorTeachingItem] {
        guard let snap = try? await db.collection("posts")
            .whereField("userId", isEqualTo: mentorId)
            .whereField("type", in: ["teaching", "sermon"])
            .order(by: "createdAt", descending: true)
            .limit(to: 8)
            .getDocuments() else { return [] }

        return snap.documents.compactMap { doc -> MentorTeachingItem? in
            let d = doc.data()
            guard let title = d["title"] as? String ?? d["body"] as? String else { return nil }
            return MentorTeachingItem(
                id:            doc.documentID,
                title:         title,
                seriesName:    d["seriesName"] as? String,
                thumbnailURL:  d["thumbnailURL"] as? String,
                durationLabel: d["durationLabel"] as? String,
                postedAt:      (d["createdAt"] as? Timestamp)?.dateValue()
            )
        }
    }

    private func fetchOfficeHours(mentorId: String) async -> [MentorOfficeHourSlot] {
        guard let snap = try? await db
            .collection("mentorAvailability")
            .document(mentorId)
            .collection("slots")
            .whereField("startTime", isGreaterThan: Timestamp(date: Date()))
            .order(by: "startTime")
            .limit(to: 5)
            .getDocuments() else { return [] }

        return snap.documents.compactMap { doc -> MentorOfficeHourSlot? in
            let d = doc.data()
            guard let start = (d["startTime"] as? Timestamp)?.dateValue(),
                  let end   = (d["endTime"]   as? Timestamp)?.dateValue() else { return nil }
            return MentorOfficeHourSlot(
                id:       doc.documentID,
                startTime: start,
                endTime:   end,
                isBooked:  d["isBooked"] as? Bool ?? false
            )
        }
    }

    private func fetchActiveDiscussions(mentorId: String) async -> [MentorActiveDiscussion] {
        guard let snap = try? await db.collection("discussions")
            .whereField("mentorId", isEqualTo: mentorId)
            .whereField("status", isEqualTo: "active")
            .limit(to: 6)
            .getDocuments() else { return [] }

        return snap.documents.compactMap { doc -> MentorActiveDiscussion? in
            let d = doc.data()
            guard let title = d["title"] as? String else { return nil }
            return MentorActiveDiscussion(
                id:               doc.documentID,
                title:            title,
                participantCount: d["participantCount"] as? Int ?? 0,
                lastActiveAt:     (d["lastActiveAt"] as? Timestamp)?.dateValue()
            )
        }
    }

    private func fetchUpcomingEvents(mentorId: String) async -> [MentorEventItem] {
        guard let snap = try? await db.collection("events")
            .whereField("hostId", isEqualTo: mentorId)
            .whereField("startDate", isGreaterThan: Timestamp(date: Date()))
            .order(by: "startDate")
            .limit(to: 5)
            .getDocuments() else { return [] }

        return snap.documents.compactMap { doc -> MentorEventItem? in
            let d = doc.data()
            guard let title = d["title"] as? String else { return nil }
            return MentorEventItem(
                id:            doc.documentID,
                title:         title,
                startAt:       (d["startDate"] as? Timestamp)?.dateValue(),
                locationLabel: d["location"] as? String,
                isOnline:      d["isOnline"] as? Bool ?? false,
                rsvpCount:     d["rsvpCount"] as? Int ?? 0
            )
        }
    }

    private func fetchStudySeries(mentorId: String) async -> [MentorStudySeries] {
        guard let snap = try? await db.collection("studies")
            .whereField("creatorId", isEqualTo: mentorId)
            .order(by: "createdAt", descending: true)
            .limit(to: 6)
            .getDocuments() else { return [] }

        let uid = Auth.auth().currentUser?.uid ?? ""

        return await withTaskGroup(of: MentorStudySeries?.self) { group in
            for doc in snap.documents {
                group.addTask {
                    let d = doc.data()
                    guard let title = d["title"] as? String else { return nil }
                    let lessonCount = d["lessonCount"] as? Int ?? 0
                    let enrollSnap = try? await Firestore.firestore()
                        .collection("studies").document(doc.documentID)
                        .collection("enrollments").document(uid)
                        .getDocument()
                    let isEnrolled = enrollSnap?.exists ?? false
                    let progress   = enrollSnap?.data()?["progressFraction"] as? Double ?? 0
                    return MentorStudySeries(
                        id:               doc.documentID,
                        title:            title,
                        lessonCount:      lessonCount,
                        isEnrolled:       isEnrolled,
                        progressFraction: progress
                    )
                }
            }
            var results: [MentorStudySeries] = []
            for await item in group {
                if let item { results.append(item) }
            }
            return results
        }
    }

    private func fetchRelatedMentors(specialties: [String]) async -> [RelatedMentorItem] {
        guard !specialties.isEmpty,
              let snap = try? await db.collection("mentors")
                  .whereField("specialties", arrayContainsAny: Array(specialties.prefix(10)))
                  .limit(to: 5)
                  .getDocuments() else { return [] }

        return snap.documents.compactMap { doc -> RelatedMentorItem? in
            let d = doc.data()
            guard let name = d["name"] as? String else { return nil }
            let specs = d["specialties"] as? [String] ?? []
            return RelatedMentorItem(
                id:               doc.documentID,
                displayName:      name,
                avatarURL:        d["photoURL"] as? String,
                primarySpecialty: specs.first
            )
        }
    }
}

// MARK: - Main View

/// Apple Music–style mentor channel: full-bleed hero → horizontal content rails.
/// Liquid Glass is used ONLY on the back button, share button, and hero action pills.
/// Rail cards use plain white + shadow, no glass.
struct AmenMentorChannelView: View {
    let mentorId: String

    @StateObject private var vm = AmenMentorChannelViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Feature flags
    @AppStorage("amen_mentor_channel_hero_enabled")  private var heroEnabled  = true
    @AppStorage("amen_mentor_channel_rails_enabled") private var railsEnabled = true

    // Nav + sheet state
    @State private var showRequestSheet    = false
    @State private var showDiscussionRoom  = false
    @State private var activeRoomType: ObjectDiscussionRoom.ObjectDiscussionRoomType = .discussion
    @State private var showSuccessToast    = false
    @State private var showAllTeachings    = false
    @State private var showAllStudySeries  = false

    // Hero collapse
    @State private var heroOffset: CGFloat = 0
    private let heroHeight: CGFloat = 340

    var body: some View {
        ZStack(alignment: .top) {
            Color(uiColor: .systemBackground).ignoresSafeArea()

            if vm.isLoading && vm.profile == nil {
                channelLoadingState
            } else if let profile = vm.profile {
                channelScrollBody(profile: profile)
            } else {
                channelEmptyState
            }

            // Floating glass nav — always on top
            floatingNav

            // Success toast
            if showSuccessToast {
                VStack {
                    Spacer()
                    toastBanner
                        .padding(.bottom, 100)
                        .transition(
                            .asymmetric(
                                insertion:  .move(edge: .bottom).combined(with: .opacity),
                                removal:    .move(edge: .bottom).combined(with: .opacity)
                            )
                        )
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .task { await vm.load(mentorId: mentorId) }
        .sheet(isPresented: $showRequestSheet) {
            MentorshipRequestSheet(mentorId: mentorId, vm: vm) {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                    showSuccessToast = true
                }
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                        showSuccessToast = false
                    }
                }
            }
        }
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
        .sheet(isPresented: $showAllTeachings) {
            NavigationStack {
                List(vm.recentTeachings) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        if let series = item.seriesName {
                            Text(series)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let date = item.postedAt {
                            Text(date, style: .date)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.insetGrouped)
                .navigationTitle("All Teachings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { showAllTeachings = false }
                            .fontWeight(.medium)
                    }
                }
            }
        }
        .sheet(isPresented: $showAllStudySeries) {
            NavigationStack {
                List(vm.studySeries) { series in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(series.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text("\(series.lessonCount) lessons")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if series.isEnrolled {
                            Text("\(Int(series.progressFraction * 100))% complete")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.insetGrouped)
                .navigationTitle("All Study Series")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { showAllStudySeries = false }
                            .fontWeight(.medium)
                    }
                }
            }
        }
    }

    // MARK: - Scroll body

    private func channelScrollBody(profile: MentorChannelProfile) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // SECTION 1: Hero
                if heroEnabled {
                    heroSection(profile: profile)
                }

                // SECTION 2: Bio card
                bioPlusStatsCard(profile: profile)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                if railsEnabled {
                    VStack(spacing: 32) {
                        // Affordance chips
                        if !vm.affordances.isEmpty {
                            AmenAffordanceChipRow(affordances: vm.affordances) { affordance in
                                handleAffordanceTap(affordance)
                            }
                            .padding(.top, 8)
                        }

                        // Rail A: Recent Teachings
                        teachingsRail

                        // Rail B: Office Hours
                        officeHoursRail(profile: profile)

                        // Rail C: Active Discussions
                        discussionsRail

                        // Rail D: Upcoming Events
                        eventsRail

                        // Rail E: Study Series
                        studySeriesRail

                        // Rail F: Prayer Availability (banner)
                        prayerAvailabilityBanner(profile: profile)
                            .padding(.horizontal, 16)

                        // SECTION 4: Related Mentors
                        relatedMentorsRail

                        Spacer(minLength: 56)
                    }
                    .padding(.top, 24)
                }
            }
        }
        .coordinateSpace(name: "mentorScroll")
    }

    // MARK: - SECTION 1: Hero

    private func heroSection(profile: MentorChannelProfile) -> some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .named("mentorScroll")).minY
            let stretch = max(0, minY)
            ZStack(alignment: .bottom) {
                // Hero image (full bleed)
                Group {
                    if let urlStr = profile.heroImageURL, let url = URL(string: urlStr) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().scaledToFill()
                            default:
                                heroPurpleGradient
                            }
                        }
                    } else {
                        heroPurpleGradient
                    }
                }
                .frame(width: geo.size.width, height: heroHeight + stretch)
                .clipped()
                .offset(y: -stretch / 2)

                // Gradient scrim — title readable at bottom
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.72)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .frame(height: heroHeight + stretch)
                .offset(y: -stretch / 2)

                // Identity + action pills
                VStack(alignment: .leading, spacing: 10) {
                    // Church badge
                    if let church = profile.churchAffiliation {
                        Text(church)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(reduceTransparency
                                          ? AnyShapeStyle(Color.black.opacity(0.55))
                                          : AnyShapeStyle(Material.ultraThinMaterial))
                            )
                            .accessibilityLabel("Church: \(church)")
                    }

                    // Name
                    Text(profile.displayName)
                        .font(.systemScaled(34, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)

                    // Tagline
                    if let tagline = profile.tagline {
                        Text(tagline)
                            .font(.systemScaled(17))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                    }

                    // Hero action pills (Liquid Glass)
                    heroActionPills(profile: profile)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .frame(height: heroHeight)
    }

    private var heroPurpleGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.28, green: 0.12, blue: 0.55),
                Color(red: 0.12, green: 0.05, blue: 0.30)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func heroActionPills(profile: MentorChannelProfile) -> some View {
        HStack(spacing: 10) {
            // Message
            heroGlassPill(icon: "message.fill", label: "Message") {
                activeRoomType = .discussion
                showDiscussionRoom = true
            }
            .accessibilityLabel("Message \(profile.displayName)")

            // Request Session
            heroGlassPill(icon: "calendar.badge.plus", label: "Request Session") {
                showRequestSheet = true
            }
            .accessibilityLabel("Request a session with \(profile.displayName)")

            // Follow / Following
            heroFollowPill(profile: profile)
        }
    }

    private func heroGlassPill(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.systemScaled(12, weight: .semibold))
                Text(label)
                    .font(.systemScaled(12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(reduceTransparency
                          ? AnyShapeStyle(Color.black.opacity(0.55))
                          : AnyShapeStyle(Material.ultraThinMaterial))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: LiquidGlassTokens.motionNormal, dampingFraction: 0.82), value: false)
    }

    private func heroFollowPill(profile: MentorChannelProfile) -> some View {
        Button {
            Task { await vm.toggleFollow(mentorId: mentorId) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: vm.isFollowing ? "bookmark.fill" : "bookmark")
                    .font(.systemScaled(12, weight: .semibold))
                Text(vm.isFollowing ? "Following" : "Follow Journey")
                    .font(.systemScaled(12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(reduceTransparency
                          ? AnyShapeStyle(vm.isFollowing
                                          ? Color.accentColor.opacity(0.8)
                                          : Color.black.opacity(0.55))
                          : AnyShapeStyle(vm.isFollowing
                                          ? AnyShapeStyle(Color.accentColor.opacity(0.55))
                                          : AnyShapeStyle(Material.ultraThinMaterial)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(vm.isFollowing ? "Following \(profile.displayName)" : "Follow \(profile.displayName)")
        .animation(.spring(response: LiquidGlassTokens.motionFast, dampingFraction: 0.85), value: vm.isFollowing)
    }

    // MARK: - SECTION 2: Bio + Stats card

    private func bioPlusStatsCard(profile: MentorChannelProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Bio expander
            if let bio = profile.bio, !bio.isEmpty {
                BioExpanderView(bio: bio)
            }

            // Specialty tag chips
            if !profile.ministeringFocus.isEmpty {
                MentorFlowLayout(profile.ministeringFocus) { tag in
                    Text(tag)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                }
            }

            Divider()

            // Stats row
            HStack(spacing: 0) {
                statCell(value: formatCount(profile.followerCount), label: "mentees")
                Divider().frame(height: 28)
                statCell(value: "\(profile.teachingCount)", label: "studies")
                Divider().frame(height: 28)
                statCell(value: "\(profile.discussionCount)", label: "discussions")
            }
            .frame(maxWidth: .infinity)

            // Availability indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(profile.officeHoursAvailable ? Color.amenSuccess : Color(.systemGray3))
                    .frame(width: 8, height: 8)
                Text(profile.officeHoursAvailable
                     ? "Available for sessions"
                     : "Sessions full")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(profile.officeHoursAvailable ? Color.amenSuccess : .secondary)
            }
            .accessibilityLabel(profile.officeHoursAvailable ? "Available for sessions" : "Sessions are currently full")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(uiColor: .separator).opacity(0.4), lineWidth: 0.5)
        )
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.systemScaled(17, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Rail header helper

    private func railHeader(title: String, seeAllAction: (() -> Void)? = nil) -> some View {
        HStack {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
            Spacer()
            if let seeAllAction {
                Button("See All", action: seeAllAction)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Rail A: Recent Teachings

    private var teachingsRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            railHeader(title: "Recent Teachings", seeAllAction: vm.recentTeachings.count > 4 ? { showAllTeachings = true } : nil)
            if vm.isLoadingTeachings {
                shimmerRail(cardWidth: 200, cardHeight: 140)
            } else if vm.recentTeachings.isEmpty {
                railEmptyLabel("No teachings yet")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(vm.recentTeachings) { item in
                            TeachingRailCard(item: item)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
                }
            }
        }
    }

    // MARK: - Rail B: Office Hours

    private func officeHoursRail(profile: MentorChannelProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            railHeader(title: "Office Hours")
            if vm.isLoadingOfficeHours {
                shimmerRail(cardWidth: 160, cardHeight: 100)
            } else if vm.officeHourSlots.isEmpty {
                // CTA card when no slots
                Button { showRequestSheet = true } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(Color.accentColor.opacity(0.14)).frame(width: 44, height: 44)
                            Image(systemName: "calendar.badge.plus")
                                .font(.systemScaled(20))
                                .foregroundStyle(Color.accentColor)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Request a Session")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("No open slots right now — send a request to \(profile.displayName.components(separatedBy: " ").first ?? "them")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.systemScaled(12, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(uiColor: .systemBackground))
                            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .accessibilityLabel("Request a session with \(profile.displayName)")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(vm.officeHourSlots) { slot in
                            OfficeHourCard(slot: slot) { showRequestSheet = true }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
                }
            }
        }
    }

    // MARK: - Rail C: Active Discussions

    private var discussionsRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            railHeader(title: "Active Discussions")
            if vm.isLoadingDiscussions {
                shimmerRail(cardWidth: 160, cardHeight: 120)
            } else if vm.activeDiscussions.isEmpty {
                railEmptyLabel("No active discussions")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(vm.activeDiscussions) { disc in
                            DiscussionRailCard(item: disc) {
                                activeRoomType = .discussion
                                showDiscussionRoom = true
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
                }
            }
        }
    }

    // MARK: - Rail D: Upcoming Events

    private var eventsRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            railHeader(title: "Upcoming Events")
            if vm.isLoadingEvents {
                shimmerRail(cardWidth: 160, cardHeight: 120)
            } else if vm.upcomingEvents.isEmpty {
                railEmptyLabel("No upcoming events")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(vm.upcomingEvents) { event in
                            EventRailCard(event: event)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
                }
            }
        }
    }

    // MARK: - Rail E: Study Series

    private var studySeriesRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            railHeader(title: "Study Series", seeAllAction: vm.studySeries.count > 4 ? { showAllStudySeries = true } : nil)
            if vm.isLoadingStudies {
                shimmerRail(cardWidth: 160, cardHeight: 120)
            } else if vm.studySeries.isEmpty {
                railEmptyLabel("No study series yet")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(vm.studySeries) { series in
                            StudySeriesRailCard(series: series)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
                }
            }
        }
    }

    // MARK: - Rail F: Prayer Availability (banner)

    private func prayerAvailabilityBanner(profile: MentorChannelProfile) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.amenPrayer.opacity(0.16)).frame(width: 48, height: 48)
                Image(systemName: "hands.and.sparkles.fill")
                    .font(.systemScaled(22))
                    .foregroundStyle(Color.amenPrayer)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Prayer Availability")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(profile.displayName.components(separatedBy: " ").first ?? "This mentor") receives prayer requests through the app")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button("Request") {
                activeRoomType = .prayer
                showDiscussionRoom = true
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.amenPrayer))
            .accessibilityLabel("Request prayer from \(profile.displayName)")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.amenPrayer.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - SECTION 4: Related Mentors

    private var relatedMentorsRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            railHeader(title: "Related Mentors")
            if vm.isLoadingRelated {
                shimmerRail(cardWidth: 120, cardHeight: 120)
            } else if vm.relatedMentors.isEmpty {
                railEmptyLabel("No related mentors found")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(vm.relatedMentors) { mentor in
                            RelatedMentorCard(item: mentor)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
                }
            }
        }
    }

    // MARK: - Shimmer placeholder rail

    private func shimmerRail(cardWidth: CGFloat, cardHeight: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(0..<3, id: \.self) { _ in
                    ShimmerRect(width: cardWidth, height: cardHeight, cornerRadius: 12)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func railEmptyLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 20)
    }

    // MARK: - Floating glass nav

    private var floatingNav: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.systemScaled(16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background {
                        Circle()
                            .fill(reduceTransparency
                                  ? AnyShapeStyle(Color.black.opacity(0.6))
                                  : AnyShapeStyle(Material.ultraThinMaterial))
                    }
                    .clipShape(Circle())
            }
            .accessibilityLabel("Back")

            Spacer()

            // Share (glass pill)
            Button {
                shareChannel()
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background {
                        Circle()
                            .fill(reduceTransparency
                                  ? AnyShapeStyle(Color.black.opacity(0.6))
                                  : AnyShapeStyle(Material.ultraThinMaterial))
                    }
                    .clipShape(Circle())
            }
            .accessibilityLabel("Share mentor channel")
        }
        .padding(.horizontal, 16)
        .padding(.top, 56)
        .animation(.spring(response: LiquidGlassTokens.motionNormal, dampingFraction: 0.82), value: heroEnabled)
    }

    // MARK: - Toast

    private var toastBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.amenSuccess)
            Text("Request sent!")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        )
    }

    // MARK: - Loading / Empty

    private var channelLoadingState: some View {
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

    private var channelEmptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "person.slash")
                .font(.systemScaled(44))
                .foregroundStyle(.tertiary)
            Text("Channel not found.")
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - Helpers

    private func handleAffordanceTap(_ affordance: ObjectAffordance) {
        switch affordance.kind {
        case .discussion:                activeRoomType = .discussion
        case .prayerRoom:               activeRoomType = .prayer
        case .studyGroup:               activeRoomType = .studyGroup
        case .membersPresent, .liveNow: activeRoomType = .discussion
        }
        showDiscussionRoom = true
    }

    private func shareChannel() {
        guard let profile = vm.profile else { return }
        let text = "Check out \(profile.displayName)'s mentor channel on AMEN."
        let vc = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first {
            window.rootViewController?.present(vc, animated: true)
        }
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 1_000_000 { return "\(n / 1_000_000)M" }
        if n >= 1_000     { return "\(n / 1_000)k" }
        return "\(n)"
    }
}

// MARK: - Bio expander

private struct BioExpanderView: View {
    let bio: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(bio)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(expanded ? nil : 3)
                .animation(.spring(response: 0.38, dampingFraction: 0.78), value: expanded)

            if bio.count > 120 {
                Button(expanded ? "Show less" : "Show more") {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                        expanded.toggle()
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Rail Card: Teaching

private struct TeachingRailCard: View {
    let item: MentorTeachingItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let urlStr = item.thumbnailURL, let url = URL(string: urlStr) {
                        AsyncImage(url: url) { phase in
                            if case .success(let img) = phase {
                                img.resizable().scaledToFill()
                            } else {
                                teachingPlaceholder
                            }
                        }
                    } else {
                        teachingPlaceholder
                    }
                }
                .frame(width: 200, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if let dur = item.durationLabel {
                    Text(dur)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.62)))
                        .padding(8)
                }
            }
            .frame(width: 200, height: 140)

            Text(item.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(width: 200, alignment: .leading)

            if let series = item.seriesName {
                Text(series)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 200, alignment: .leading)
            }
        }
        .shadow(color: .black.opacity(0.07), radius: 8, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.title + (item.seriesName.map { " – \($0)" } ?? ""))
    }

    private var teachingPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.28, green: 0.12, blue: 0.55).opacity(0.12))
            Image(systemName: "play.rectangle.fill")
                .font(.systemScaled(30))
                .foregroundStyle(Color(red: 0.28, green: 0.12, blue: 0.55).opacity(0.35))
        }
    }
}

// MARK: - Rail Card: Office Hours

private struct OfficeHourCard: View {
    let slot: MentorOfficeHourSlot
    let onBook: () -> Void

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "clock.fill")
                    .font(.systemScaled(14))
                    .foregroundStyle(Color.accentColor)
                Spacer()
                if slot.isBooked {
                    Text("Booked")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color(.systemGray5)))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(Self.dateFormatter.string(from: slot.startTime))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(Self.timeFormatter.string(from: slot.startTime)) – \(Self.timeFormatter.string(from: slot.endTime))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !slot.isBooked {
                Button("Book", action: onBook)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.accentColor))
            }
        }
        .padding(12)
        .frame(width: 160)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.07), radius: 8, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(uiColor: .separator).opacity(0.3), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            slot.isBooked
            ? "Slot on \(Self.dateFormatter.string(from: slot.startTime)) is booked"
            : "Available slot on \(Self.dateFormatter.string(from: slot.startTime)). Book button."
        )
    }
}

// MARK: - Rail Card: Discussion

private struct DiscussionRailCard: View {
    let item: MentorActiveDiscussion
    let onTap: () -> Void

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.amenScripture.opacity(0.12))
                        .frame(height: 48)
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.systemScaled(20))
                        .foregroundStyle(Color.amenScripture)
                }

                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.systemScaled(10))
                        .foregroundStyle(.secondary)
                    Text("\(item.participantCount)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let last = item.lastActiveAt {
                        Text(Self.relativeFormatter.localizedString(for: last, relativeTo: Date()))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(12)
            .frame(width: 160)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .systemBackground))
                    .shadow(color: .black.opacity(0.07), radius: 8, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(uiColor: .separator).opacity(0.3), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.title), \(item.participantCount) participants")
    }
}

// MARK: - Rail Card: Event

private struct EventRailCard: View {
    let event: MentorEventItem

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                // Calendar date block
                VStack(spacing: 0) {
                    if let date = event.startAt {
                        Text(Self.monthFormatter.string(from: date).uppercased())
                            .font(.systemScaled(9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 3)
                            .background(Color.amenError)

                        Text(Self.dayFormatter.string(from: date))
                            .font(.systemScaled(18, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background(Color(uiColor: .systemGray6))
                    }
                }
                .frame(width: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color(uiColor: .separator).opacity(0.4), lineWidth: 0.5)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Image(systemName: event.isOnline ? "video.fill" : "mappin.circle.fill")
                        .font(.systemScaled(11))
                        .foregroundStyle(event.isOnline ? Color.amenInfo : Color.amenWarning)
                    Text(event.isOnline ? "Online" : "In Person")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if event.rsvpCount > 0 {
                    Text("\(event.rsvpCount) going")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(event.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if let date = event.startAt {
                Text(Self.timeFormatter.string(from: date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 160)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.07), radius: 8, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(uiColor: .separator).opacity(0.3), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.title), \(event.isOnline ? "online" : event.locationLabel ?? "in person")")
    }
}

// MARK: - Rail Card: Study Series

private struct StudySeriesRailCard: View {
    let series: MentorStudySeries

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(height: 52)
                Image(systemName: "books.vertical.fill")
                    .font(.systemScaled(22))
                    .foregroundStyle(Color.accentColor)
            }

            Text(series.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text("\(series.lessonCount) lessons")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if series.isEnrolled {
                VStack(alignment: .leading, spacing: 3) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(.systemGray5)).frame(height: 4)
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: geo.size.width * series.progressFraction, height: 4)
                        }
                    }
                    .frame(height: 4)
                    Text("\(Int(series.progressFraction * 100))% complete")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding(12)
        .frame(width: 160)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.07), radius: 8, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(uiColor: .separator).opacity(0.3), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(series.isEnrolled
                            ? "\(series.title), \(series.lessonCount) lessons, \(Int(series.progressFraction * 100)) percent complete"
                            : "\(series.title), \(series.lessonCount) lessons")
    }
}

// MARK: - Rail Card: Related Mentor

private struct RelatedMentorCard: View {
    let item: RelatedMentorItem

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let urlStr = item.avatarURL, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                        } else {
                            initialsCircle
                        }
                    }
                } else {
                    initialsCircle
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color(uiColor: .separator).opacity(0.3), lineWidth: 0.5))

            Text(item.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 100)

            if let spec = item.primarySpecialty {
                Text(spec)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 100)
            }
        }
        .frame(width: 110)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.displayName + (item.primarySpecialty.map { " – \($0)" } ?? ""))
    }

    private var initialsCircle: some View {
        ZStack {
            Circle().fill(Color(red: 0.28, green: 0.12, blue: 0.55).opacity(0.12))
            Text(item.displayName
                .components(separatedBy: " ")
                .prefix(2)
                .compactMap { $0.first.map(String.init) }
                .joined()
                .uppercased()
            )
            .font(.systemScaled(24, weight: .semibold))
            .foregroundStyle(Color(red: 0.28, green: 0.12, blue: 0.55))
        }
    }
}

// MARK: - Shimmer placeholder

private struct ShimmerRect: View {
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat

    @State private var phase: CGFloat = 0

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color(.systemGray5), location: phase - 0.3),
                        .init(color: Color(.systemGray4), location: phase),
                        .init(color: Color(.systemGray5), location: phase + 0.3)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: width, height: height)
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1.6
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Flow layout (wrapping tag row)

private struct MentorFlowLayout<Data: RandomAccessCollection, Content: View>: View
    where Data.Element: Hashable {
    let data: Data
    let content: (Data.Element) -> Content

    init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data    = data
        self.content = content
    }

    var body: some View {
        var width:  CGFloat = 0
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

// MARK: - SECTION 5: Mentorship Request Sheet

private struct MentorshipRequestSheet: View {
    let mentorId: String
    @ObservedObject var vm: AmenMentorChannelViewModel
    let onSuccess: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var goal:         String = ""
    @State private var message:      String = ""
    @State private var availability: String = "Morning"
    @State private var isSubmitting  = false
    @State private var showError     = false

    private let availabilityOptions = ["Morning", "Afternoon", "Evening", "Flexible"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Your Goal") {
                    TextEditor(text: $goal)
                        .frame(minHeight: 80)
                        .accessibilityLabel("Describe your mentorship goal")
                }

                Section("Preferred Availability") {
                    Picker("Availability", selection: $availability) {
                        ForEach(availabilityOptions, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Select preferred availability")
                }

                Section("Message to Mentor (optional)") {
                    TextEditor(text: $message)
                        .frame(minHeight: 80)
                        .accessibilityLabel("Write an optional message to the mentor")
                }
            }
            .navigationTitle("Request Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Send")
                        }
                    }
                    .disabled(goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                }
            }
            .alert("Could not send request", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please check your connection and try again.")
            }
        }
        .presentationDetents([.large])
    }

    private func submit() async {
        isSubmitting = true
        let success = await vm.submitMentorshipRequest(
            mentorId:     mentorId,
            goal:         goal,
            availability: availability,
            message:      message
        )
        isSubmitting = false
        if success {
            dismiss()
            onSuccess()
        } else {
            showError = true
        }
    }
}
