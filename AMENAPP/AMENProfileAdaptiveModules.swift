//
//  AMENProfileAdaptiveModules.swift
//  AMENAPP
//
//  Injectable profile module views for Personal, Church, and Business accounts.
//  These are STANDALONE components — they do NOT modify UserProfileView or ProfileView.
//  Designed to be embedded in any profile page.
//
//  No Firebase. Pure SwiftUI.
//

import SwiftUI

// MARK: - Liquid Glass Helpers (local to this file)

private struct GlassCard<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat = 16

    init(cornerRadius: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.white.opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 4)
            )
    }
}

private struct GlassCapsule<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(Color.white.opacity(0.55)))
                    .overlay(Capsule().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 3)
            )
    }
}

// MARK: - 1. ProfileAdaptiveModulesView

struct ProfileAdaptiveModulesView: View {
    let accountType: AMENAccountType

    // Dummy data for previewing without Firebase
    var body: some View {
        VStack(spacing: 12) {
            switch accountType {
            case .personal:
                personalModules
            case .church:
                churchModules
            case .business:
                businessModules
            case .school:
                churchModules
            case .university:
                churchModules
            }
        }
    }

    @ViewBuilder
    private var personalModules: some View {
        let items: [AnyView] = [
            AnyView(ChurchAffiliationBadgeView(
                churchName: "Pillar Church",
                relationshipLabel: "Attends",
                visibility: "Public",
                onTap: {}
            )),
            AnyView(PersonalFaithJourneyModuleView(
                currentSeason: "Studying the book of Romans",
                prayerFocusItems: ["Healing", "Wisdom", "Family"],
                verseTopics: ["Grace", "Faith"],
                onEdit: {}
            )),
            AnyView(PersonalPrayerFocusModuleView(
                prayerFocus: "Seeking guidance for the next season",
                onAdd: {}
            )),
            AnyView(PersonalTestimonyModuleView(
                testimonySnippet: "God brought me through a season of loss and reminded me that His plans are higher than my own.",
                hasMoreContent: true,
                onView: {}
            ))
        ]
        ForEach(Array(items.enumerated()), id: \.offset) { index, view in
            view
                .staggeredEntrance(index: index)
        }
    }

    @ViewBuilder
    private var churchModules: some View {
        let items: [AnyView] = [
            AnyView(ChurchVerificationBadgeView(isVerified: true, onVerify: {})),
            AnyView(ChurchMutualSignalView(mutualCount: 18, areaDescription: "Atlanta, GA")),
            AnyView(ChurchServiceTimesModuleView(serviceTimes: [
                (day: "Sunday", time: "9:00 AM", label: "Traditional"),
                (day: "Sunday", time: "11:00 AM", label: "Contemporary"),
                (day: "Wednesday", time: "7:00 PM", label: "Midweek"),
                (day: "Friday", time: "6:30 PM", label: "Youth"),
                (day: "Saturday", time: "5:00 PM", label: "Evening")
            ])),
            AnyView(ChurchVisitCTAView(onPlanVisit: {}, onDirections: {}))
        ]
        ForEach(Array(items.enumerated()), id: \.offset) { index, view in
            view
                .staggeredEntrance(index: index)
        }
    }

    @ViewBuilder
    private var businessModules: some View {
        let items: [AnyView] = [
            AnyView(BusinessMissionModuleView(
                category: "Media",
                missionStatement: "Equipping believers through gospel-centered content and resources.",
                websiteURL: "amenapp.com",
                contactEmail: "hello@amenapp.com",
                onVisitSite: {}
            )),
            AnyView(BusinessFeaturedOfferingModuleView(
                offeringTitle: "Faith & Work Masterclass",
                offeringDescription: "A 6-week journey through integrating your faith into your daily work life.",
                onView: {}
            )),
            AnyView(BusinessLinksModuleView(links: [
                (label: "Resource Library", icon: "books.vertical.fill"),
                (label: "Newsletter", icon: "envelope.fill"),
                (label: "Podcast", icon: "mic.fill"),
                (label: "Community", icon: "person.3.fill")
            ]))
        ]
        ForEach(Array(items.enumerated()), id: \.offset) { index, view in
            view
                .staggeredEntrance(index: index)
        }
    }
}

private extension View {
    func staggeredEntrance(index: Int) -> some View {
        self.modifier(StaggeredEntranceModifier(index: index))
    }
}

private struct StaggeredEntranceModifier: ViewModifier {
    let index: Int
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .offset(y: appeared ? 0 : 20)
            .opacity(appeared ? 1 : 0)
            .onAppear {
                withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.82)).delay(Double(index) * 0.06)) {
                    appeared = true
                }
            }
    }
}

// MARK: - 2. ChurchAffiliationBadgeView

struct ChurchAffiliationBadgeView: View {
    let churchName: String
    let relationshipLabel: String
    let visibility: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            GlassCapsule {
                HStack(spacing: 8) {
                    Image(systemName: "building.columns.fill")
                        .font(.systemScaled(13, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text("\(relationshipLabel) \(churchName)")
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 0)

                    Text(visibility)
                        .font(AMENFont.regular(11))
                        .foregroundStyle(.tertiary)

                    Image(systemName: "chevron.right")
                        .font(.systemScaled(10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 3. ChurchServiceTimesModuleView

struct ChurchServiceTimesModuleView: View {
    let serviceTimes: [(day: String, time: String, label: String)]

    private var visibleTimes: [(day: String, time: String, label: String)] {
        Array(serviceTimes.prefix(4))
    }

    private var overflowCount: Int {
        max(0, serviceTimes.count - 4)
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("Service Times")
                    .font(AMENFont.bold(15))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                Divider()
                    .background(Color(white: 0.88))

                ForEach(Array(visibleTimes.enumerated()), id: \.offset) { _, entry in
                    HStack(spacing: 0) {
                        Text(entry.day)
                            .font(AMENFont.semiBold(13))
                            .foregroundStyle(.primary)
                            .frame(minWidth: 80, alignment: .leading)

                        Text(entry.time)
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 80, alignment: .leading)

                        Text(entry.label)
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)

                    if visibleTimes.indices.last.map({ $0 != visibleTimes.count - 1 }) == true {
                        Divider()
                            .padding(.leading, 16)
                            .background(Color(white: 0.92))
                    }
                }

                if overflowCount > 0 {
                    Divider()
                        .background(Color(white: 0.88))

                    HStack {
                        Spacer()
                        Text("+\(overflowCount) more  ·  See all")
                            .font(AMENFont.semiBold(12))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                }
            }
            .padding(.bottom, 4)
        }
    }
}

// MARK: - 4. ChurchVisitCTAView

struct ChurchVisitCTAView: View {
    let onPlanVisit: () -> Void
    let onDirections: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Plan your visit")
                        .font(AMENFont.bold(16))
                        .foregroundStyle(.primary)

                    Text("First-time? Here's what to expect.")
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button(action: onPlanVisit) {
                        Text("Plan a Visit")
                            .font(AMENFont.semiBold(13))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(.black))
                    }
                    .buttonStyle(.plain)

                    Button(action: onDirections) {
                        GlassCapsule {
                            Text("Get Directions")
                                .font(AMENFont.semiBold(13))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }
}

// MARK: - 5. ChurchMutualSignalView

struct ChurchMutualSignalView: View {
    let mutualCount: Int
    let areaDescription: String?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                if mutualCount > 0 {
                    HStack(spacing: 8) {
                        // Avatar placeholder circles
                        HStack(spacing: -8) {
                            ForEach(0..<min(mutualCount, 3), id: \.self) { _ in
                                Circle()
                                    .fill(Color(white: 0.80))
                                    .frame(width: 26, height: 26)
                                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
                            }
                        }

                        Text("\(mutualCount) of your mutuals attend here")
                            .font(AMENFont.semiBold(13))
                            .foregroundStyle(.primary)
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "person.3.fill")
                            .font(.systemScaled(14))
                            .foregroundStyle(.secondary)
                        Text(areaDescription.map { "Many in \($0) connect here" } ?? "Many in your area connect here")
                            .font(AMENFont.semiBold(13))
                            .foregroundStyle(.primary)
                    }
                }

                // Signal chips
                HStack(spacing: 8) {
                    signalChip("Active this week")
                    signalChip("New sermon discussion today")
                }
            }
            .padding(14)
        }
    }

    private func signalChip(_ label: String) -> some View {
        Text(label)
            .font(AMENFont.regular(11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color(white: 0.93).opacity(0.8))
            )
    }
}

// MARK: - 6. ChurchVerificationBadgeView

struct ChurchVerificationBadgeView: View {
    let isVerified: Bool
    let onVerify: () -> Void

    var body: some View {
        GlassCard {
            if isVerified {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(.black)
                            .frame(width: 30, height: 30)
                        Image(systemName: "checkmark")
                            .font(.systemScaled(13, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Verified Church")
                            .font(AMENFont.bold(14))
                            .foregroundStyle(.primary)
                        Text("Identity confirmed by AMEN")
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(14)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.systemScaled(16))
                            .foregroundStyle(.tertiary)
                        Text("Verify this church account")
                            .font(AMENFont.semiBold(14))
                            .foregroundStyle(.primary)
                    }

                    Text("Verification adds trust and unlocks additional features for your community.")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Button(action: onVerify) {
                        Text("Start verification")
                            .font(AMENFont.semiBold(12))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .strokeBorder(.black.opacity(0.25), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
            }
        }
    }
}

// MARK: - 7. PersonalFaithJourneyModuleView

struct PersonalFaithJourneyModuleView: View {
    let currentSeason: String?
    let prayerFocusItems: [String]
    let verseTopics: [String]
    let onEdit: () -> Void

    var isEmpty: Bool {
        currentSeason == nil && prayerFocusItems.isEmpty && verseTopics.isEmpty
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Faith Journey")
                        .font(AMENFont.bold(15))
                        .foregroundStyle(.primary)
                    Spacer()
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.systemScaled(13, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }

                if isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "leaf.fill")
                            .font(.systemScaled(13))
                            .foregroundStyle(.tertiary)
                        Text("Share what you're growing through")
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    if let season = currentSeason {
                        Text(season)
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if !prayerFocusItems.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Prayer focus")
                                .font(AMENFont.semiBold(11))
                                .foregroundStyle(.tertiary)
                            chipRow(prayerFocusItems)
                        }
                    }

                    if !verseTopics.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Verse topics")
                                .font(AMENFont.semiBold(11))
                                .foregroundStyle(.tertiary)
                            chipRow(verseTopics)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func chipRow(_ items: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(Color(white: 0.93).opacity(0.85))
                        )
                }
            }
        }
    }
}

// MARK: - 8. PersonalPrayerFocusModuleView

struct PersonalPrayerFocusModuleView: View {
    let prayerFocus: String?
    let onAdd: () -> Void

    var body: some View {
        GlassCard {
            if let focus = prayerFocus {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "hands.and.sparkles.fill")
                        .font(.systemScaled(18))
                        .foregroundStyle(.tertiary)
                        .frame(width: 26, height: 26)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(focus)
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.primary)
                            .lineLimit(3)

                        Text("Updated 2 days ago")
                            .font(AMENFont.regular(11))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()
                }
                .padding(14)
            } else {
                Button(action: onAdd) {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle")
                            .font(.systemScaled(16))
                            .foregroundStyle(.tertiary)
                        Text("Add a prayer focus")
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .padding(14)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - 9. PersonalTestimonyModuleView

struct PersonalTestimonyModuleView: View {
    let testimonySnippet: String?
    let hasMoreContent: Bool
    let onView: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Testimony")
                    .font(AMENFont.bold(15))
                    .foregroundStyle(.primary)

                if let snippet = testimonySnippet {
                    let preview = snippet.count > 80
                        ? String(snippet.prefix(80)).appending("…")
                        : snippet

                    Text(preview)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)

                    if hasMoreContent {
                        Button(action: onView) {
                            Text("Read more →")
                                .font(AMENFont.semiBold(12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Button(action: onView) {
                        HStack(spacing: 8) {
                            Image(systemName: "text.book.closed")
                                .font(.systemScaled(14))
                                .foregroundStyle(.tertiary)
                            Text("Share your story")
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }
}

// MARK: - 10. BusinessMissionModuleView

struct BusinessMissionModuleView: View {
    let category: String
    let missionStatement: String?
    let websiteURL: String?
    let contactEmail: String?
    let onVisitSite: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                // Category chip
                Text(category)
                    .font(AMENFont.semiBold(11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(Color(white: 0.92).opacity(0.9))
                    )

                if let mission = missionStatement {
                    Text(mission)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                if websiteURL != nil || contactEmail != nil {
                    Divider()
                        .background(Color(white: 0.88))

                    HStack(spacing: 16) {
                        if let url = websiteURL {
                            Button(action: onVisitSite) {
                                Label(url, systemImage: "globe")
                                    .font(AMENFont.regular(12))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        if let email = contactEmail {
                            Label(email, systemImage: "envelope")
                                .font(AMENFont.regular(12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(16)
        }
    }
}

// MARK: - 11. BusinessLinksModuleView

struct BusinessLinksModuleView: View {
    let links: [(label: String, icon: String)]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("Links & Resources")
                    .font(AMENFont.bold(15))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                Divider()
                    .background(Color(white: 0.88))

                ForEach(Array(links.prefix(4).enumerated()), id: \.offset) { index, link in
                    HStack(spacing: 12) {
                        Image(systemName: link.icon)
                            .font(.systemScaled(14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 20)

                        Text(link.label)
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.primary)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.systemScaled(11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    if index < min(links.count, 4) - 1 {
                        Divider()
                            .padding(.leading, 48)
                            .background(Color(white: 0.92))
                    }
                }
            }
            .padding(.bottom, 4)
        }
    }
}

// MARK: - 12. BusinessFeaturedOfferingModuleView

struct BusinessFeaturedOfferingModuleView: View {
    let offeringTitle: String?
    let offeringDescription: String?
    let onView: () -> Void

    var body: some View {
        GlassCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Featured")
                    .font(AMENFont.semiBold(11))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .tracking(0.8)

                if let title = offeringTitle {
                    Text(title)
                        .font(AMENFont.bold(16))
                        .foregroundStyle(.primary)

                    if let desc = offeringDescription {
                        Text(desc)
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Button(action: onView) {
                        Text("View")
                            .font(AMENFont.semiBold(13))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(.black))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                } else {
                    Button(action: onView) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle")
                                .font(.systemScaled(15))
                                .foregroundStyle(.tertiary)
                            Text("Add your featured offering")
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
        }
    }
}

// MARK: - 13. SmartEngagementSignalChipRow

struct SmartEngagementSignalChipRow: View {
    let signals: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(signals, id: \.self) { signal in
                    Text(signal)
                        .font(AMENFont.regular(11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .overlay(Capsule().fill(Color.white.opacity(0.55)))
                                .overlay(Capsule().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                                .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                        )
                }
            }
            .padding(.horizontal, 1)
        }
    }
}

// MARK: - 14. ProfileActionBarView

struct ProfileActionBarView: View {
    let accountType: AMENAccountType
    let isCurrentUser: Bool
    let onAction: (String) -> Void

    private var actions: [(label: String, isPrimary: Bool)] {
        if isCurrentUser {
            return [
                ("Edit Profile", true),
                ("Share Profile", false)
            ]
        }
        switch accountType {
        case .personal:
            return [
                ("Follow", true),
                ("Message", false),
                ("Pray With", false)
            ]
        case .church:
            return [
                ("Plan Visit", true),
                ("Message", false),
                ("Events", false),
                ("Sermon", false)
            ]
        case .business:
            return [
                ("Contact", true),
                ("Collaborate", false),
                ("Visit Site", false)
            ]
        case .school:
            return [
                ("Connect", true),
                ("Message", false),
                ("Events", false)
            ]
        case .university:
            return [
                ("Connect", true),
                ("Message", false),
                ("Chapel", false)
            ]
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(actions, id: \.label) { action in
                    Button {
                        onAction(action.label)
                    } label: {
                        Text(action.label)
                            .font(AMENFont.semiBold(13))
                            .foregroundStyle(action.isPrimary ? .white : .black)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(
                                Group {
                                    if action.isPrimary {
                                        AnyView(Capsule().fill(.black))
                                    } else {
                                        AnyView(
                                            Capsule()
                                                .fill(.ultraThinMaterial)
                                                .overlay(Capsule().fill(Color.white.opacity(0.55)))
                                                .overlay(Capsule().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                                                .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 3)
                                        )
                                    }
                                }
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
    }
}

// MARK: - Previews

struct AMENProfileAdaptiveModules_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Personal Modules")
                    .font(AMENFont.bold(18))
                ProfileAdaptiveModulesView(accountType: .personal)

                Divider()

                Text("Church Modules")
                    .font(AMENFont.bold(18))
                ProfileAdaptiveModulesView(accountType: .church)

                Divider()

                Text("Business Modules")
                    .font(AMENFont.bold(18))
                ProfileAdaptiveModulesView(accountType: .business)

                Divider()

                Text("Profile Action Bar — Church")
                    .font(AMENFont.bold(15))
                ProfileActionBarView(accountType: .church, isCurrentUser: false, onAction: { _ in })

                Text("Profile Action Bar — Own Profile")
                    .font(AMENFont.bold(15))
                ProfileActionBarView(accountType: .personal, isCurrentUser: true, onAction: { _ in })

                Text("Smart Signal Chip Row")
                    .font(AMENFont.bold(15))
                SmartEngagementSignalChipRow(signals: [
                    "Many were encouraged",
                    "Active discussion",
                    "Saved by many"
                ])
            }
            .padding(16)
        }
        .background(Color.white)
        .previewDisplayName("All Profile Modules")
    }
}
