// FeaturedSmartModuleCard.swift
// AMEN — Creator Profiles (ministry hubs) — Wave 3
//
// "What matters right now" hero card. The SERVER decides what to feature
// (CreatorHubFeaturedModule); the client only renders it with the correct CTA.
// When the server has nothing to feature (nil) the card degrades gracefully,
// deriving a calm prompt from the resolved heroState.
//
// Conventions: white bg / black primary text; ONE translucent glass card (no
// glass-on-glass — children are flat over the glass parent); AmenTheme.Colors.* +
// Color(hex:) tokens; Dynamic Type (text styles only); VoiceOver labels on the CTA
// and a combined card element; Live state pulses unless reduce-motion is on.

import SwiftUI

struct FeaturedSmartModuleCard: View {
    let featured: CreatorHubFeaturedModule?
    let heroState: CreatorHubHeroState

    /// CTA tap — surfaced so the parent can route into the relevant module/player.
    var onPrimaryAction: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let featured {
                content(for: featured)
            } else {
                emptyContent
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .amenGlassCard(cornerRadius: 22)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Featured content (server-selected)

    @ViewBuilder
    private func content(for featured: CreatorHubFeaturedModule) -> some View {
        switch featured {
        case .live(let event):
            heroBody(
                eyebrow: "Live now",
                eyebrowTint: Color(hex: "E0394B"),
                eyebrowIcon: "dot.radiowaves.left.and.right",
                pulsing: true,
                title: event.title,
                subtitle: subtitle(for: event),
                cta: "Join live",
                ctaIcon: "play.fill"
            )
        case .nextEvent(let event):
            heroBody(
                eyebrow: "Up next",
                eyebrowTint: AmenTheme.Colors.amenGoldText,
                eyebrowIcon: "calendar",
                pulsing: false,
                title: event.title,
                subtitle: countdownSubtitle(for: event),
                cta: "View event",
                ctaIcon: "calendar"
            )
        case .latestTeaching(let teaching):
            heroBody(
                eyebrow: "Latest teaching",
                eyebrowTint: AmenTheme.Colors.statusInfo,
                eyebrowIcon: "play.circle",
                pulsing: false,
                title: teaching.title,
                subtitle: teachingSubtitle(for: teaching),
                cta: "Play teaching",
                ctaIcon: "play.fill"
            )
        case .newResource(let resource):
            heroBody(
                eyebrow: "New resource",
                eyebrowTint: AmenTheme.Colors.amenGoldText,
                eyebrowIcon: "doc.text",
                pulsing: false,
                title: resource.title,
                subtitle: resource.kind.rawValue.capitalized,
                cta: "Open resource",
                ctaIcon: "arrow.up.right"
            )
        case .featuredCourse(let course):
            heroBody(
                eyebrow: "Featured course",
                eyebrowTint: AmenTheme.Colors.statusSuccess,
                eyebrowIcon: "graduationcap",
                pulsing: false,
                title: course.title,
                subtitle: courseSubtitle(for: course),
                cta: "Start course",
                ctaIcon: "graduationcap.fill"
            )
        }
    }

    // MARK: - Empty content (derived from heroState)

    @ViewBuilder
    private var emptyContent: some View {
        switch heroState {
        case .live(let event):
            heroBody(
                eyebrow: "Live now",
                eyebrowTint: Color(hex: "E0394B"),
                eyebrowIcon: "dot.radiowaves.left.and.right",
                pulsing: true,
                title: event.title,
                subtitle: subtitle(for: event),
                cta: "Join live",
                ctaIcon: "play.fill"
            )
        case .nextEvent(let event):
            heroBody(
                eyebrow: "Up next",
                eyebrowTint: AmenTheme.Colors.amenGoldText,
                eyebrowIcon: "calendar",
                pulsing: false,
                title: event.title,
                subtitle: countdownSubtitle(for: event),
                cta: "View event",
                ctaIcon: "calendar"
            )
        case .latestTeaching(let teaching):
            heroBody(
                eyebrow: "Latest teaching",
                eyebrowTint: AmenTheme.Colors.statusInfo,
                eyebrowIcon: "play.circle",
                pulsing: false,
                title: teaching.title,
                subtitle: teachingSubtitle(for: teaching),
                cta: "Play teaching",
                ctaIcon: "play.fill"
            )
        case .resource(let resource):
            heroBody(
                eyebrow: "Resource",
                eyebrowTint: AmenTheme.Colors.amenGoldText,
                eyebrowIcon: "doc.text",
                pulsing: false,
                title: resource.title,
                subtitle: resource.kind.rawValue.capitalized,
                cta: "Open resource",
                ctaIcon: "arrow.up.right"
            )
        case .prayer(let openRequests):
            calmEmptyBody(
                icon: "hands.sparkles",
                title: openRequests > 0 ? "\(openRequests) prayer requests" : "Prayer board",
                message: "Stand with this ministry in prayer."
            )
        case .idle:
            calmEmptyBody(
                icon: "sparkles",
                title: "Nothing featured right now",
                message: "Explore teachings, events, and courses below."
            )
        }
    }

    // MARK: - Hero body

    private func heroBody(
        eyebrow: String,
        eyebrowTint: Color,
        eyebrowIcon: String,
        pulsing: Bool,
        title: String,
        subtitle: String?,
        cta: String,
        ctaIcon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: eyebrowIcon)
                    .imageScale(.small)
                    .modifier(FeaturedPulseModifier(active: pulsing && !reduceMotion))
                Text(eyebrow.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(0.5)
            }
            .foregroundStyle(eyebrowTint)

            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .lineLimit(2)
            }

            primaryButton(title: cta, icon: ctaIcon)
        }
    }

    private func calmEmptyBody(icon: String, title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(AmenTheme.Colors.amenGoldText)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func primaryButton(title: String, icon: String) -> some View {
        Button(action: onPrimaryAction) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .imageScale(.small)
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(AmenTheme.Colors.buttonPrimaryText)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(Capsule().fill(AmenTheme.Colors.buttonPrimary))
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
        .accessibilityLabel(title)
    }

    // MARK: - Subtitle helpers

    private func subtitle(for event: CreatorHubEvent) -> String {
        var parts: [String] = [event.type.displayLabel]
        if let name = event.geo?.locationName, !name.isEmpty {
            parts.append(name)
        }
        return parts.joined(separator: " · ")
    }

    private func countdownSubtitle(for event: CreatorHubEvent) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: event.timeZone) ?? .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: event.startsAt)
    }

    private func teachingSubtitle(for teaching: CreatorHubTeaching) -> String {
        var parts: [String] = []
        if let series = teaching.series, !series.isEmpty { parts.append(series) }
        if !teaching.speakers.isEmpty { parts.append(teaching.speakers.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    private func courseSubtitle(for course: CreatorHubCourse) -> String {
        let moduleCount = course.modules.count
        let lessonCount = course.modules.reduce(0) { $0 + $1.lessons.count }
        return "\(moduleCount) modules · \(lessonCount) lessons"
    }
}

// MARK: - Event type display labels (shared by Creator Hub event surfaces)

extension CreatorHubEventType {
    var displayLabel: String {
        switch self {
        case .sermon:        return "Sermon"
        case .bibleStudy:    return "Bible Study"
        case .worshipNight:  return "Worship Night"
        case .conference:    return "Conference"
        case .class:         return "Class"
        case .prayerMeeting: return "Prayer Meeting"
        case .livestream:    return "Livestream"
        case .revival:       return "Revival"
        case .webinar:       return "Webinar"
        case .mentorship:    return "Mentorship"
        case .smallGroup:    return "Small Group"
        }
    }
}

// MARK: - Pulse (reduce-motion aware)

private struct FeaturedPulseModifier: ViewModifier {
    let active: Bool
    @State private var pulse = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(active && pulse ? 1.25 : 1.0)
            .opacity(active && pulse ? 0.55 : 1.0)
            .onAppear {
                guard active else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}
