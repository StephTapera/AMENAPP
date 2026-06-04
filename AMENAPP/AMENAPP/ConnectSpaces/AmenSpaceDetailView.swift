// AmenSpaceDetailView.swift
// AMEN ConnectSpaces — Full Space detail page
//
// Design constraints:
//   - Hero + parallax at top via AmenSpaceHeroHeaderView
//   - Paywall: ZStack overlay with .ultraThinMaterial + CTA when !isSubscribed
//   - Event cards and post rows are inline (no separate sub-view references)
//   - "Open Room" is a floating glass pill, NOT part of the scroll content
//   - Scroll offset tracked via an invisible anchor preference key

import SwiftUI
import FirebaseAuth

// MARK: - Scroll offset preference key

private struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Stub post model (local to this view)

private struct SpacePostStub: Identifiable {
    let id: String
    let title: String
    let timestamp: Date
}

private let previewPosts: [SpacePostStub] = [
    SpacePostStub(id: "p1", title: "Sunday sermon recap — Romans 8", timestamp: Date().addingTimeInterval(-3600)),
    SpacePostStub(id: "p2", title: "Prayer request: healing for my father",   timestamp: Date().addingTimeInterval(-7200)),
    SpacePostStub(id: "p3", title: "New study guide for this week's passage",  timestamp: Date().addingTimeInterval(-86400)),
    SpacePostStub(id: "p4", title: "Upcoming retreat registration is open",    timestamp: Date().addingTimeInterval(-172800))
]

// MARK: - Date formatter helper

private let relativeFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .short
    return f
}()

// MARK: - Event type icon

private func eventTypeIcon(_ type: AmenSpaceEventType) -> String {
    switch type {
    case .livestream:          return "dot.radiowaves.left.and.right"
    case .audioHuddle:         return "waveform.circle"
    case .communityEvent:      return "person.3.fill"
    case .recurringGathering:  return "arrow.clockwise.circle"
    case .prayerMeeting:       return "hands.sparkles.fill"
    case .studySession:        return "book.closed.fill"
    }
}

// MARK: - Upcoming event card (inline)

private struct UpcomingEventCard: View {
    let event: AmenSpaceEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: eventTypeIcon(event.type))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: "D9A441"))
                Text(event.type.rawValue.capitalized)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: "D9A441").opacity(0.85))
            }

            Text(event.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(spacing: 12) {
                Label(
                    event.scheduledAt.formatted(date: .abbreviated, time: .shortened),
                    systemImage: "calendar"
                )
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.55))

                Label(
                    "\(event.rsvpUserIds.count) going",
                    systemImage: "person.2"
                )
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.55))
            }
        }
        .padding(14)
        .frame(width: 220, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(hex: "D9A441").opacity(0.18), lineWidth: 0.5)
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.title), scheduled \(event.scheduledAt.formatted(date: .abbreviated, time: .shortened)), \(event.rsvpUserIds.count) attending")
    }
}

// MARK: - Post row card (inline, matte glass)

private struct SpacePostRow: View {
    let post: SpacePostStub

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(post.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(relativeFormatter.localizedString(for: post.timestamp, relativeTo: Date()))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.45))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.28))
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(post.title)
    }
}

// MARK: - Paywall overlay

private struct PaywallOverlay: View {
    let onJoin: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            // Blur over locked content
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color(hex: "D9A441"))

                Text("Members only")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)

                Text("Join this Space to read posts, attend events, and connect with the community.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.70))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button(action: onJoin) {
                    Text("Join to unlock")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(hex: "070607"))
                        .padding(.horizontal, 32)
                        .padding(.vertical, 13)
                        .background {
                            Capsule(style: .continuous)
                                .fill(Color(hex: "D9A441"))
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Join to unlock this Space")
            }
            .padding(.bottom, 48)
        }
    }
}

// MARK: - Section header (glass pill, matches HubView pattern)

private func sectionHeader(title: String, accent: Color) -> some View {
    Text(title.uppercased())
        .font(.system(size: 11, weight: .bold))
        .kerning(1.2)
        .foregroundStyle(accent)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(accent.opacity(0.25), lineWidth: 0.5)
                }
        }
        .padding(.horizontal, 16)
}

// MARK: - Main view

struct AmenSpaceDetailView: View {
    let space: AmenConnectSpacesSpace
    let events: [AmenSpaceEvent]
    let tiers: [AmenSpaceSubscriptionTier]
    let hostProfile: AmenVerifiedHostProfile?

    @State private var isSubscribed = false
    @State private var scrollOffset: CGFloat = 0
    @State private var showRoom = false
    @State private var showCommunityInsights = false
    private var currentUserId: String { Auth.auth().currentUser?.uid ?? "" }
    private var isCreator: Bool { space.createdBy == currentUserId }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isVerified: Bool {
        hostProfile?.verificationStatus == .verified
    }

    private var hostBadge: AmenHostBadgeVariant {
        hostProfile?.badgeVariant ?? .individual
    }

    private var hostDisplayName: String {
        hostProfile?.displayName ?? space.createdBy
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Matte page background
                Color(red: 0.027, green: 0.024, blue: 0.031)
                    .ignoresSafeArea()

                // MARK: Scrollable content
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Scroll offset anchor
                        GeometryReader { proxy in
                            Color.clear
                                .preference(
                                    key: ScrollOffsetKey.self,
                                    value: proxy.frame(in: .named("scroll")).minY
                                )
                        }
                        .frame(height: 0)

                        // Hero header
                        AmenSpaceHeroHeaderView(
                            spaceName: space.name,
                            hostDisplayName: hostDisplayName,
                            memberCount: space.memberIds.count,
                            isSubscribed: isSubscribed,
                            isVerified: isVerified,
                            hostBadge: hostBadge,
                            scrollOffset: scrollOffset,
                            onJoin: { withAnimation { isSubscribed = true } },
                            onLeave: { withAnimation { isSubscribed = false } }
                        )

                        // Spiritual OS: hero card section — passes real spaceName; bannerURL added when AmenConnectSpacesSpace gains the field
                        AmenSpacesHeroCardSection(
                            spaceId: space.id,
                            bannerURL: nil,
                            spaceName: space.name
                        )

                        VStack(alignment: .leading, spacing: 24) {
                            // MARK: Coming Up section
                            if !events.isEmpty {
                                sectionHeader(title: "Coming Up", accent: Color(hex: "D9A441"))
                                    .padding(.top, 20)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(events.sorted(by: { $0.scheduledAt < $1.scheduledAt })) { event in
                                            UpcomingEventCard(event: event)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 4)
                                }
                            }

                            // MARK: Posts section
                            sectionHeader(title: "Posts", accent: Color(hex: "6E4BB5"))
                                .padding(.top, events.isEmpty ? 20 : 0)

                            // Paywall gate wrapping the feed
                            ZStack(alignment: .bottom) {
                                LazyVStack(spacing: 10) {
                                    ForEach(previewPosts) { post in
                                        SpacePostRow(post: post)
                                    }
                                }
                                .padding(.horizontal, 16)
                                // Slight blur at bottom when locked so content is hinted but gated
                                .blur(radius: isSubscribed ? 0 : 6)
                                .allowsHitTesting(isSubscribed)

                                if !isSubscribed {
                                    PaywallOverlay {
                                        withAnimation(reduceMotion ? .easeInOut(duration: 0.01) : .spring(response: 0.38, dampingFraction: 0.78)) {
                                            isSubscribed = true
                                        }
                                    }
                                }
                            }
                            .frame(minHeight: 280)

                            // Community OS: insights button shown to space creator only
                            if isCreator {
                                Button {
                                    showCommunityInsights = true
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "waveform.path.ecg")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(Color(hex: "6E4BB5"))
                                        Text("Community Insights")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(.white)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Color.white.opacity(0.4))
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 13)
                                    .background {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(.ultraThinMaterial)
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .strokeBorder(Color(hex: "6E4BB5").opacity(0.35), lineWidth: 0.5)
                                            }
                                    }
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 16)
                                .accessibilityLabel("View Community Insights for \(space.name)")
                            }

                            // Bottom padding so content isn't hidden behind floating pill
                            Spacer(minLength: 100)
                        }
                    }
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(ScrollOffsetKey.self) { value in
                    scrollOffset = value
                }

                // MARK: Floating "Open Room" pill
                Button {
                    showRoom = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.wave.2.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(hex: "D9A441"))
                        Text("Open Room")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
                    .background {
                        Capsule(style: .continuous)
                            .fill(.thinMaterial)
                            .overlay {
                                Capsule(style: .continuous)
                                    .strokeBorder(Color(hex: "D9A441").opacity(0.35), lineWidth: 0.5)
                            }
                    }
                    .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 6)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 24)
                .accessibilityLabel("Open Ministry Room for \(space.name)")
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
            .sheet(isPresented: $showRoom) {
                AmenMinistryRoomShellView(space: space)
            }
            .sheet(isPresented: $showCommunityInsights) {
                AmenCommunityOSView(spaceId: space.id, spaceName: space.name)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
private let previewSpace = AmenConnectSpacesSpace(
    id: "space-preview",
    name: "Sunday Worship Team",
    type: .worship,
    memberIds: Array(repeating: "u", count: 2841),
    careSensitivity: false,
    createdBy: "elevation_church",
    createdAt: Date(),
    updatedAt: Date()
)

private let previewHostProfile = AmenVerifiedHostProfile(
    id: "space-preview",
    hostType: .church,
    verificationStatus: .verified,
    displayName: "Elevation Church",
    ein: "12-3456789",
    verifiedAt: Date(),
    badgeVariant: .church
)

private let previewEvents: [AmenSpaceEvent] = [
    AmenSpaceEvent(
        id: "evt-1",
        spaceId: "space-preview",
        hostUserId: "elevation_church",
        title: "Sunday Live Worship",
        eventDescription: "Join us for live worship this Sunday.",
        type: .livestream,
        scheduledAt: Date().addingTimeInterval(86400),
        durationMinutes: 90,
        isRecurring: true,
        recurrenceRule: "RRULE:FREQ=WEEKLY;BYDAY=SU",
        rsvpUserIds: ["u1", "u2", "u3", "u4"],
        maxAttendees: nil,
        requiredTierId: nil,
        isLive: false,
        liveRoomId: nil,
        replayRef: nil,
        calendarInviteSentAt: nil,
        createdAt: Date(),
        updatedAt: Date()
    ),
    AmenSpaceEvent(
        id: "evt-2",
        spaceId: "space-preview",
        hostUserId: "elevation_church",
        title: "Wednesday Prayer Meeting",
        eventDescription: "Midweek corporate prayer.",
        type: .prayerMeeting,
        scheduledAt: Date().addingTimeInterval(3 * 86400),
        durationMinutes: 45,
        isRecurring: true,
        recurrenceRule: "RRULE:FREQ=WEEKLY;BYDAY=WE",
        rsvpUserIds: ["u1", "u5"],
        maxAttendees: 50,
        requiredTierId: nil,
        isLive: false,
        liveRoomId: nil,
        replayRef: nil,
        calendarInviteSentAt: nil,
        createdAt: Date(),
        updatedAt: Date()
    )
]

#Preview("Detail — not subscribed") {
    AmenSpaceDetailView(
        space: previewSpace,
        events: previewEvents,
        tiers: [],
        hostProfile: previewHostProfile
    )
    .preferredColorScheme(.dark)
}

#Preview("Detail — subscribed") {
    AmenSpaceDetailView(
        space: previewSpace,
        events: previewEvents,
        tiers: [],
        hostProfile: previewHostProfile
    )
    .preferredColorScheme(.dark)
    .onAppear {}
}
#endif
