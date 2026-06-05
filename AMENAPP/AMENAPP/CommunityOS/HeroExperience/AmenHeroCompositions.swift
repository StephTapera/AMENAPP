// AmenHeroCompositions.swift
// AMEN App — Community OS › Hero Experience
//
// Phase 5 Agent D2 — Hero Experience
// Surface-specific hero compositions built on top of AmenHeroHeader.
// Each composition wires domain model fields to the generic AmenHeroHeader API
// and injects the appropriate AmenGlassDarkPill action row.
//
// Surfaces covered:
//   - AmenChurchHero      — Church Profile (.standard, Verified badge + 3 pills)
//   - AmenEventHero       — Event Detail (.standard, date subtitle + RSVP/Share pills)
//   - AmenDiscussionHero  — Discussion Room (.compact, room-type badge + Join pill)
//   - AmenProfileHero     — User/Org Profile (.standard, cover + floating avatar)
//
// AmenGlassDarkPill is also defined here as the shared over-photo button primitive.
//
// Design contract (C3):
//   - NO custom hex colors — system semantics + AmenDesignSystem tokens only
//   - AmenGlassDarkPill: black.opacity(0.55) capsule + white text — the ONLY valid
//     way to place buttons over hero photos
//   - All images provide accessibilityLabel; text is Dynamic Type only
//   - accessibilityReduceMotion respected by AmenProgressiveHeroView (separate file)

import SwiftUI

// MARK: — AmenGlassDarkPill
//
// The "Directions button" pattern from C3 §6.
// Dark translucent capsule readable over any photo.
// This is the ONLY approved way to place action buttons over hero images.

struct AmenGlassDarkPill: View {

    let label: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.55))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        // Minimum 44pt touch target via the intrinsic capsule + padding
    }
}

// MARK: — AmenChurchHero

/// Hero header for the Church Profile surface (C6 §3.4 — `/church/{churchId}`).
/// Rendered at .standard height (280pt) with a Verified badge and three action pills.
///
/// Accepts individual fields rather than a model type so it remains usable before
/// CommunityOS/Church/AmenChurchModels (A8) merges.
/// When A8 merges, add a convenience init(church: AmenChurch, ...) extension.
struct AmenChurchHero: View {

    let churchName: String
    let denomination: String?
    let coverImageUrl: String?
    let isVerified: Bool
    let givingEnabled: Bool

    var onFollow: () -> Void
    var onVisit: () -> Void
    var onGive: () -> Void

    var body: some View {
        AmenHeroHeader(
            imageUrl: coverImageUrl,
            title: churchName,
            subtitle: denomination,
            badge: isVerified ? "Verified" : nil,
            height: .standard
        ) {
            HStack(spacing: 8) {
                AmenGlassDarkPill(
                    label: "Follow",
                    systemImage: "plus.circle",
                    action: onFollow
                )
                AmenGlassDarkPill(
                    label: "Visit",
                    systemImage: "location.fill",
                    action: onVisit
                )
                if givingEnabled {
                    AmenGlassDarkPill(
                        label: "Give",
                        systemImage: "heart.fill",
                        action: onGive
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isVerified ? "\(churchName), Verified" : churchName)
    }
}

// MARK: — AmenEventHero

/// Hero header for the Event Detail surface (C6 §3.5 — `/event/{eventId}`).
/// Rendered at .standard height (280pt) with the date/organizer subtitle and RSVP + Share pills.
struct AmenEventHero: View {

    let title: String
    let organizer: String
    let coverImageUrl: String?
    let date: Date

    var onRSVP: () -> Void
    var onShare: () -> Void

    var body: some View {
        AmenHeroHeader(
            imageUrl: coverImageUrl,
            title: title,
            subtitle: subtitleText,
            badge: nil,
            height: .standard
        ) {
            HStack(spacing: 8) {
                AmenGlassDarkPill(
                    label: "RSVP",
                    systemImage: "checkmark.circle",
                    action: onRSVP
                )
                AmenGlassDarkPill(
                    label: "Share",
                    systemImage: "square.and.arrow.up",
                    action: onShare
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title), \(organizer), \(subtitleText)")
    }

    private var subtitleText: String {
        let formatted = date.formatted(date: .abbreviated, time: .shortened)
        return "\(organizer) \u{2022} \(formatted)"
    }
}

// MARK: — AmenDiscussionHero

/// Hero header for Discussion Rooms (C6 §3.3 — discovery entry point).
/// Rendered at .compact height (200pt) with the room-type badge and a single Join pill.
struct AmenDiscussionHero: View {

    let title: String
    let roomType: String        // e.g. "Bible Study", "Prayer Circle"
    let coverImageUrl: String?

    var onJoin: () -> Void

    var body: some View {
        AmenHeroHeader(
            imageUrl: coverImageUrl,
            title: title,
            subtitle: nil,
            badge: roomType,
            height: .compact
        ) {
            AmenGlassDarkPill(
                label: "Join",
                systemImage: "person.crop.circle.badge.plus",
                action: onJoin
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title), \(roomType) room")
    }
}

// MARK: — AmenProfileHero

/// Hero header for user and organisation profiles (C6 §3.4).
/// Shows the cover photo at .standard height with a 72pt avatar circle
/// overlapping the bottom edge by 36pt, plus optional action pills.
///
/// The avatar is placed outside the ClipShape via a ZStack overlay so
/// its white border ring is never clipped.
struct AmenProfileHero: View {

    let displayName: String
    let tagline: String?
    let avatarUrl: String?
    let coverImageUrl: String?
    var onMessage: (() -> Void)? = nil
    var onFollow: (() -> Void)? = nil

    // Avatar diameter + half-overlap constants
    private let avatarSize: CGFloat = 72
    private let avatarOverlap: CGFloat = 36

    var body: some View {
        ZStack(alignment: .bottomLeading) {

            // Cover hero — title is displayed below the card, not over the photo
            AmenHeroHeader(
                imageUrl: coverImageUrl,
                title: "",
                subtitle: nil,
                badge: nil,
                height: .standard
            ) {
                // Optional action pills for non-own profiles
                if onMessage != nil || onFollow != nil {
                    HStack(spacing: 8) {
                        if let onMessage {
                            AmenGlassDarkPill(
                                label: "Message",
                                systemImage: "bubble.left",
                                action: onMessage
                            )
                        }
                        if let onFollow {
                            AmenGlassDarkPill(
                                label: "Follow",
                                systemImage: "plus.circle",
                                action: onFollow
                            )
                        }
                    }
                }
            }

            // Avatar circle — overlaps the bottom edge of the hero by avatarOverlap
            AsyncImage(url: URL(string: avatarUrl ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Color(uiColor: .systemGray4)
                }
            }
            .frame(width: avatarSize, height: avatarSize)
            .clipShape(Circle())
            .overlay(
                Circle().strokeBorder(Color.white, lineWidth: 3)
            )
            .shadow(
                color: Color.black.opacity(AmenShadow.card.opacity),
                radius: AmenShadow.card.radius,
                x: AmenShadow.card.x,
                y: AmenShadow.card.y
            )
            .offset(x: 16, y: avatarOverlap)
            .accessibilityLabel("\(displayName)'s profile photo")
        }
        // Extra bottom padding so callers can place the name + tagline below
        .padding(.bottom, avatarOverlap)
    }
}

// MARK: — Preview

#if DEBUG

#Preview("Church Hero — verified, giving enabled") {
    ScrollView {
        VStack(spacing: 20) {
            AmenChurchHero(
                churchName: "Crosspoint Church",
                denomination: "Non-Denominational",
                coverImageUrl: nil,
                isVerified: true,
                givingEnabled: true,
                onFollow: {},
                onVisit: {},
                onGive: {}
            )
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 20)
    }
    .background(Color(uiColor: .systemGroupedBackground))
}

#Preview("Event Hero") {
    AmenEventHero(
        title: "Young Adult Night",
        organizer: "Crosspoint Church",
        coverImageUrl: nil,
        date: Date().addingTimeInterval(3600 * 24),
        onRSVP: {},
        onShare: {}
    )
    .padding(20)
    .background(Color(uiColor: .systemGroupedBackground))
}

#Preview("Discussion Room Hero") {
    AmenDiscussionHero(
        title: "Romans 8 Deep Dive",
        roomType: "Bible Study",
        coverImageUrl: nil,
        onJoin: {}
    )
    .padding(20)
    .background(Color(uiColor: .systemGroupedBackground))
}

#Preview("Profile Hero") {
    VStack(spacing: 0) {
        AmenProfileHero(
            displayName: "Sarah Johnson",
            tagline: "Walking in faith daily",
            avatarUrl: nil,
            coverImageUrl: nil,
            onMessage: {},
            onFollow: {}
        )
        VStack(alignment: .leading, spacing: 4) {
            Text("Sarah Johnson")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color(uiColor: .label))
            Text("Walking in faith daily")
                .font(.subheadline)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
        .padding(.top, 44)  // room for the overlapping avatar
        .padding(.leading, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
    }
    .background(Color(uiColor: .systemGroupedBackground))
}

#Preview("GlassDarkPill variants") {
    HStack(spacing: 12) {
        AmenGlassDarkPill(label: "Follow", systemImage: "plus.circle") {}
        AmenGlassDarkPill(label: "RSVP", systemImage: "checkmark.circle") {}
        AmenGlassDarkPill(label: "Give", systemImage: "heart.fill") {}
    }
    .padding(20)
    .background(Color.black.opacity(0.5))
}
#endif
