// FindChurch2SmartChurchCard.swift
// AMENAPP — Find Church 2.0, Wave 3
//
// Adaptive church card that changes its lead content based on SeekerProfile.SeekerIntent.
// One glass card surface — no nested glass.
//
// Design rules:
//   - Glass: .ultraThinMaterial only — no custom Color + opacity stack
//   - No glass-on-glass nesting
//   - Luminous border: Color.white.opacity(0.45) at 0.5pt
//   - Shadow: radius 4, y 2, opacity 0.10
//   - Interactive targets ≥ 44×44pt
//   - @Environment(\.accessibilityReduceMotion) guards all animations
//   - Dynamic Type: .font(.system(.<style>)) — no fixed sizes

import SwiftUI
import Foundation
import CoreLocation

// MARK: - AvailabilityPill (private)

private struct AvailabilityPill: View {
    enum Kind { case serviceToday, openNow, livestream }

    let kind: Kind
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(pillColor)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(pillLabel)
                .font(.system(.caption2).weight(.semibold))
                .foregroundStyle(pillColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(pillBackground)
        .overlay(pillBorder)
        .clipShape(Capsule(style: .continuous))
        .accessibilityLabel(pillLabel)
    }

    private var pillLabel: String {
        switch kind {
        case .serviceToday: return "Service Today"
        case .openNow:      return "Open Now"
        case .livestream:   return "Livestream"
        }
    }

    private var pillColor: Color {
        switch kind {
        case .serviceToday: return .blue
        case .openNow:      return .green
        case .livestream:   return Color(red: 0.55, green: 0.20, blue: 0.90)
        }
    }

    @ViewBuilder
    private var pillBackground: some View {
        if reduceTransparency {
            Capsule(style: .continuous).fill(Color(.secondarySystemBackground))
        } else {
            Capsule(style: .continuous).fill(pillColor.opacity(0.12))
        }
    }

    private var pillBorder: some View {
        Capsule(style: .continuous)
            .strokeBorder(pillColor.opacity(0.35), lineWidth: 0.5)
    }
}

// MARK: - GatheringCountBadge (private)

private struct GatheringCountBadge: View {
    let count: Int

    var body: some View {
        Label("\(count) gathering\(count == 1 ? "" : "s")", systemImage: "person.2.fill")
            .font(.system(.caption).weight(.medium))
            .foregroundStyle(.secondary)
            .accessibilityLabel("\(count) gathering\(count == 1 ? "" : "s") available")
    }
}

// MARK: - MemberCountHint (private)

private struct MemberCountHint: View {
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "person.3.fill")
                .font(.system(.caption))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(formattedCount)
                .font(.system(.caption).weight(.medium))
                .foregroundStyle(.secondary)
            Text("in AMEN")
                .font(.system(.caption))
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(count) AMEN members attend this church")
    }

    private var formattedCount: String {
        count >= 1000
            ? String(format: "%.1fk", Double(count) / 1000)
            : "\(count)"
    }
}

// MARK: - FindChurch2SmartChurchCard

/// Adaptive church result card. Layout varies by the caller's primary SeekerIntent.
struct FindChurch2SmartChurchCard: View {
    let church: ChurchObject
    let match: MatchExplanation?
    let intent: SeekerProfile.SeekerIntent
    let availability: AvailabilityStatus
    let userLocation: CLLocation?       // optional — nil omits distance
    let showMatchExplain: Bool          // pass AMENFeatureFlags.shared.findChurch2MatchExplainEnabled

    init(
        church: ChurchObject,
        match: MatchExplanation?,
        intent: SeekerProfile.SeekerIntent,
        availability: AvailabilityStatus,
        userLocation: CLLocation? = nil,
        showMatchExplain: Bool = false
    ) {
        self.church = church
        self.match = match
        self.intent = intent
        self.availability = availability
        self.userLocation = userLocation
        self.showMatchExplain = showMatchExplain
    }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Lead section — varies by intent
            leadSection
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 16)

            // Shared footer
            footerSection
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .background(cardBackground)
        .overlay(cardBorder)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 2)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Lead section routing

    @ViewBuilder
    private var leadSection: some View {
        switch intent {
        case .visitSunday, .findChurch:
            visitSundayLead
        case .watchOnline:
            watchOnlineLead
        case .bibleStudy:
            bibleStudyLead
        case .findCommunity:
            findCommunityLead
        default:
            defaultLead
        }
    }

    // MARK: Visit Sunday / Find Church lead

    private var visitSundayLead: some View {
        VStack(alignment: .leading, spacing: 8) {
            churchNameRow

            // Service time + availability pill row
            HStack(spacing: 8) {
                if let time = availability.serviceTime {
                    Label(time, systemImage: "clock.fill")
                        .font(.system(.subheadline))
                        .foregroundStyle(.primary)
                        .accessibilityLabel("Service at \(time)")
                }

                if availability.serviceToday {
                    AvailabilityPill(kind: .serviceToday)
                }
                if availability.openNow {
                    AvailabilityPill(kind: .openNow)
                }
            }

            // "What to expect" hint
            Text("Visitors welcome · Casual dress · Parking available")
                .font(.system(.caption))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityLabel("Visitors welcome, casual dress, parking available")
        }
    }

    // MARK: Watch online lead

    private var watchOnlineLead: some View {
        VStack(alignment: .leading, spacing: 8) {
            churchNameRow

            HStack(spacing: 8) {
                if availability.livestreamActive {
                    AvailabilityPill(kind: .livestream)
                } else if let time = availability.serviceTime {
                    Label(time, systemImage: "clock.fill")
                        .font(.system(.subheadline))
                        .foregroundStyle(.primary)
                        .accessibilityLabel("Service at \(time)")
                }
            }

            if church.mediaLinks.hasMedia {
                HStack(spacing: 4) {
                    mediaTypeIcon
                    Text(mediaTypeLabel)
                        .font(.system(.caption))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var mediaTypeIcon: some View {
        let name: String = {
            switch church.mediaLinks.detectedMediaType {
            case .youtube:    return "play.rectangle.fill"
            case .podcast:    return "mic.fill"
            case .livestream: return "dot.radiowaves.left.and.right"
            default:          return "video.fill"
            }
        }()
        return Image(systemName: name)
            .font(.system(.caption))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }

    private var mediaTypeLabel: String {
        switch church.mediaLinks.detectedMediaType {
        case .youtube:    return "YouTube sermons available"
        case .podcast:    return "Podcast available"
        case .livestream: return "Livestream available"
        case .multiple:   return "Multiple media streams"
        case .none:       return ""
        }
    }

    // MARK: Bible study lead

    private var bibleStudyLead: some View {
        VStack(alignment: .leading, spacing: 8) {
            churchNameRow

            if church.gatheringIds.count > 0 {
                GatheringCountBadge(count: church.gatheringIds.count)
            } else {
                Label("Contact for study groups", systemImage: "person.fill.questionmark")
                    .font(.system(.caption))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Find community lead

    private var findCommunityLead: some View {
        VStack(alignment: .leading, spacing: 8) {
            churchNameRow

            MemberCountHint(count: church.amenMemberCount)

            if !church.ministryTags.isEmpty {
                let tags = church.ministryTags.prefix(3).joined(separator: " · ")
                Text(tags)
                    .font(.system(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: Default lead

    private var defaultLead: some View {
        VStack(alignment: .leading, spacing: 8) {
            churchNameRow

            HStack(spacing: 8) {
                if let distanceStr = distanceString {
                    Label(distanceStr, systemImage: "location.fill")
                        .font(.system(.subheadline))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(distanceStr + " away")
                }
                if let denomination = church.denomination {
                    Text(denomination)
                        .font(.system(.caption))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Shared church name row

    private var churchNameRow: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(church.name)
                    .font(.system(.title2).weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let city = church.city as String?, !city.isEmpty {
                    Text("\(city)\(church.state.map { ", \($0)" } ?? "")")
                        .font(.system(.caption))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            verificationBadge
        }
    }

    @ViewBuilder
    private var verificationBadge: some View {
        switch church.verificationTier {
        case .ein, .manual:
            Image(systemName: "checkmark.seal.fill")
                .font(.system(.subheadline))
                .foregroundStyle(.blue)
                .accessibilityLabel("Verified church")
        case .domain:
            Image(systemName: "checkmark.seal")
                .font(.system(.subheadline))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Domain verified")
        case .none:
            EmptyView()
        }
    }

    // MARK: - Footer section

    private var footerSection: some View {
        HStack(spacing: 10) {
            // Distance (shown in footer unless already shown in lead)
            if let distanceStr = distanceString, intent != .findChurch && intent != .visitSunday {
                Label(distanceStr, systemImage: "location")
                    .font(.system(.caption))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(distanceStr + " away")
            }

            Spacer()

            // Match badge
            if let match = match {
                FindChurch2MatchBadge(match: match, showExplainSheet: showMatchExplain)
            }
        }
    }

    // MARK: - Helpers

    private var distanceString: String? {
        guard let userLocation else { return nil }
        let miles = church.coordinate.distance(from: userLocation)
        if miles < 0.1 { return "Nearby" }
        if miles < 10  { return String(format: "%.1f mi", miles) }
        return String(format: "%.0f mi", miles)
    }

    // MARK: - Card backgrounds

    @ViewBuilder
    private var cardBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5)
    }
}

// MARK: - Previews

#if DEBUG
private let _previewChurch = ChurchObject(
    id: "preview-1",
    placeId: nil,
    ein: nil,
    name: "Grace Community Church",
    normalizedName: "grace community church",
    address: "123 Faith Ave",
    normalizedAddress: "123 faith ave",
    city: "Nashville",
    state: "TN",
    zipCode: "37201",
    country: "US",
    coordinate: .init(latitude: 36.162, longitude: -86.781),
    phoneNumber: nil,
    email: nil,
    website: nil,
    photoURL: nil,
    logoURL: nil,
    denomination: "Non-denominational",
    denominationFamily: nil,
    denominationIsFlexible: true,
    denominationLineage: [],
    beliefs: nil,
    serviceTimes: [
        StructuredServiceTime(dayOfWeek: 1, startHour: 10, startMinute: 30)
    ],
    mediaLinks: .init(detectedMediaType: .youtube),
    accessibility: .init(),
    claimState: .verified,
    verificationTier: .domain,
    claimedBy: nil,
    claimedAt: nil,
    childSafetyPolicy: .init(),
    staffCount: nil,
    ministryTags: ["youth", "women", "recovery"],
    gatheringIds: ["g1", "g2", "g3"],
    availabilityCache: nil,
    availabilityCachedAt: nil,
    pendingServiceTimeSuggestions: 0,
    amenMemberCount: 142,
    visitCount: 48,
    friendSavedCount: 3,
    source: .googlePlaces,
    createdAt: Date(),
    updatedAt: Date(),
    isDeleted: false
)

private let _previewAvailability = AvailabilityStatus(
    openNow: false,
    serviceToday: true,
    serviceTime: "10:30 AM",
    studyTonight: false,
    livestreamActive: false,
    prayerAvailable: false,
    contactNeeded: false,
    computedAt: Date()
)

private let _previewMatch = MatchExplanation(
    score: 78,
    topReasons: [
        .init(category: .distance, label: "1.4 mi away", weight: 0.9, isPositive: true),
        .init(category: .serviceTime, label: "Sunday 10:30 AM", weight: 0.8, isPositive: true)
    ],
    mismatches: [],
    generatedBy: "local",
    generatedAt: Date()
)

#Preview("Visit Sunday intent") {
    ScrollView {
        FindChurch2SmartChurchCard(
            church: _previewChurch,
            match: _previewMatch,
            intent: .visitSunday,
            availability: _previewAvailability,
            showMatchExplain: true
        )
        .padding()
    }
}

#Preview("Watch Online intent") {
    ScrollView {
        FindChurch2SmartChurchCard(
            church: _previewChurch,
            match: _previewMatch,
            intent: .watchOnline,
            availability: _previewAvailability,
            showMatchExplain: false
        )
        .padding()
    }
}

#Preview("Bible Study intent") {
    ScrollView {
        FindChurch2SmartChurchCard(
            church: _previewChurch,
            match: _previewMatch,
            intent: .bibleStudy,
            availability: _previewAvailability,
            showMatchExplain: true
        )
        .padding()
    }
}
#endif
