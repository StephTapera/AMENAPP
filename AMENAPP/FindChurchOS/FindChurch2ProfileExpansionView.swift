// FindChurch2ProfileExpansionView.swift
// AMENAPP — Find Church 2.0, Wave 6
//
// Card → full church profile sheet with matchedGeometryEffect transition.
// Design rules (HARD — do not relax):
//   - Glass: .ultraThinMaterial only — no nested materials, no custom opacity stacks
//   - Luminous border: Color.white.opacity(0.45) strokeBorder 0.5 pt
//   - Shadow: radius 4, y 2, opacity 0.10
//   - matchedGeometryEffect ONLY when !reduceMotion — else plain .sheet transition
//   - .animation(.spring(response:0.45, dampingFraction:0.82)) on the sheet transition
//   - All tap targets ≥ 44×44 pt
//   - Dynamic Type text styles only — no fixed point sizes
//   - No force-unwrap
//
// Components in this file:
//   FindChurch2ChurchProfileSheet   — full scrollable profile sheet
//   FindChurch2CardToProfileTransition — ViewModifier applied to SmartChurchCard
//
// Depends on:
//   FindChurch2Contracts.swift           — ChurchObject, MatchExplanation,
//                                          AvailabilityStatus, SeekerProfile
//   FindChurch2CommunitySignalsView.swift — FindChurch2CommunitySignals, FindChurch2AvatarCluster
//   FindChurch2TrustSignalsView.swift     — FindChurch2TrustSignalsView
//   FindChurch2VisitPlannerView.swift     — FindChurch2VisitPlannerView
//   FindChurch2ConciergeView.swift        — FindChurch2ConciergeView
//   FindChurch2ClaimView.swift            — FindChurch2ClaimButton
//   AMENFeatureFlags.swift               — flag checks

import SwiftUI
import Foundation

// MARK: - AvailabilityPillRow (private)

/// Compact row of availability pills for the profile sheet header.
/// Renders only the pills relevant to the current AvailabilityStatus.
private struct AvailabilityPillRow: View {

    let availability: AvailabilityStatus

    var body: some View {
        if !hasPills {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if availability.openNow {
                        ProfileAvailabilityPill(kind: .openNow)
                    }
                    if availability.serviceToday, let time = availability.serviceTime {
                        ProfileAvailabilityPill(kind: .serviceToday(time: time))
                    } else if availability.serviceToday {
                        ProfileAvailabilityPill(kind: .serviceToday(time: nil))
                    }
                    if availability.livestreamActive {
                        ProfileAvailabilityPill(kind: .livestream)
                    }
                    if availability.studyTonight {
                        ProfileAvailabilityPill(kind: .studyTonight)
                    }
                    if availability.prayerAvailable {
                        ProfileAvailabilityPill(kind: .prayer)
                    }
                    if availability.contactNeeded {
                        ProfileAvailabilityPill(kind: .contactNeeded)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
            .accessibilityElement(children: .contain)
        }
    }

    private var hasPills: Bool {
        availability.openNow ||
        availability.serviceToday ||
        availability.livestreamActive ||
        availability.studyTonight ||
        availability.prayerAvailable ||
        availability.contactNeeded
    }
}

// MARK: - ProfileAvailabilityPill (private)

private struct ProfileAvailabilityPill: View {

    enum Kind {
        case openNow
        case serviceToday(time: String?)
        case livestream
        case studyTonight
        case prayer
        case contactNeeded
    }

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
        case .openNow:                    return "Open Now"
        case .serviceToday(let time):
            if let t = time { return "Service \(t)" }
            return "Service Today"
        case .livestream:                 return "Livestream"
        case .studyTonight:               return "Study Tonight"
        case .prayer:                     return "Prayer Available"
        case .contactNeeded:              return "Contact for Times"
        }
    }

    private var pillColor: Color {
        switch kind {
        case .openNow:        return .green
        case .serviceToday:   return .blue
        case .livestream:     return Color(red: 0.55, green: 0.20, blue: 0.90)
        case .studyTonight:   return Color(red: 0.90, green: 0.50, blue: 0.10)
        case .prayer:         return Color(red: 0.85, green: 0.70, blue: 0.20)
        case .contactNeeded:  return .secondary
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

// MARK: - BeliefTagsSection (private)

/// Beliefs section shown only when church.claimState == .verified AND church.beliefs != nil.
private struct BeliefTagsSection: View {

    let beliefs: BeliefSchema

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let tags = beliefs.allTags
        if tags.isEmpty { EmptyView() } else {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("What We Believe")

                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 110, maximum: 240), spacing: 8, alignment: .leading)
                    ],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(tags, id: \.self) { tag in
                        BeliefPill(tag: tag, reduceTransparency: reduceTransparency)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Church beliefs: \(tags.map { "\($0.category) \($0.value)" }.joined(separator: ", "))")
            }
        }
    }
}

// MARK: - BeliefPill (private)

private struct BeliefPill: View {
    let tag: BeliefTag
    let reduceTransparency: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(tag.category)
                .font(.system(.caption2).weight(.medium))
                .foregroundStyle(.secondary)
            Text(tag.value)
                .font(.system(.caption2).weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(background)
        .overlay(border)
        .clipShape(Capsule(style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tag.category): \(tag.value)")
    }

    @ViewBuilder
    private var background: some View {
        if reduceTransparency {
            Capsule(style: .continuous).fill(Color(.secondarySystemBackground))
        } else {
            Capsule(style: .continuous).fill(.ultraThinMaterial)
        }
    }

    private var border: some View {
        Capsule(style: .continuous)
            .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5)
    }
}

// MARK: - SaveShareFooter (private)

private struct SaveShareFooter: View {

    let churchName: String
    @State private var isSaved: Bool = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 12) {
            saveButton
            Spacer()
            shareButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(footerBackground)
        .overlay(footerBorder)
        .clipShape(Capsule(style: .continuous))
    }

    private var saveButton: some View {
        Button {
            isSaved.toggle()
        } label: {
            Label(isSaved ? "Saved" : "Save", systemImage: isSaved ? "bookmark.fill" : "bookmark")
                .font(.system(.subheadline).weight(.medium))
                .foregroundStyle(isSaved ? Color(red: 0.85, green: 0.70, blue: 0.20) : .primary)
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityLabel(isSaved ? "Remove from saved churches" : "Save \(churchName)")
    }

    private var shareButton: some View {
        Button {
            // Share sheet — wired by caller if needed; UI only here
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
                .font(.system(.subheadline).weight(.medium))
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityLabel("Share \(churchName)")
    }

    @ViewBuilder
    private var footerBackground: some View {
        if reduceTransparency {
            Capsule(style: .continuous).fill(Color(.secondarySystemBackground))
        } else {
            Capsule(style: .continuous).fill(.ultraThinMaterial)
        }
    }

    private var footerBorder: some View {
        Capsule(style: .continuous)
            .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5)
    }
}

// MARK: - SectionHeader helper (private free function)

private func sectionHeader(_ title: String) -> some View {
    Text(title)
        .font(.system(.title3).weight(.semibold))
        .foregroundStyle(.primary)
        .accessibilityAddTraits(.isHeader)
}

// MARK: - FindChurch2ChurchProfileSheet

/// Full church profile presented as a sheet. Accepts a `namespace` and `cardId` from
/// the parent list to drive a `matchedGeometryEffect` on the church name when
/// `reduceMotion` is false.
///
/// The `matchedGeometryEffect` is applied to the church name `Text` at the top of the
/// sheet header. The parent must hold the same `@Namespace` and pass the matching ID.
struct FindChurch2ChurchProfileSheet: View {

    // MARK: Interface

    let church: ChurchObject
    let match: MatchExplanation?
    let availability: AvailabilityStatus
    let comfortPrefs: [SeekerProfile.ComfortChip]

    var namespace: Namespace.ID
    let cardId: String

    // MARK: State

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ObservedObject private var flags = AMENFeatureFlags.shared

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // 1. Header: name + address + distance
                    headerSection

                    // 2. Availability pills
                    AvailabilityPillRow(availability: availability)
                        .padding(.horizontal, 20)

                    Divider()
                        .padding(.horizontal, 20)

                    // 3. Community signals
                    communitySignalsSection

                    // 4. Trust signals (gated by flag inside FindChurch2TrustSignalsView)
                    FindChurch2TrustSignalsView(church: church)
                        .padding(.horizontal, 20)

                    // 5. Visit planner entry point (flag-gated)
                    if flags.findChurch2VisitPlannerEnabled {
                        visitPlannerSection
                    }

                    // 6. Concierge entry point (flag-gated)
                    if flags.findChurch2ConciergeEnabled {
                        conciergeSection
                    }

                    // 7. Beliefs section (verified only)
                    if church.claimState == .verified, let beliefs = church.beliefs {
                        BeliefTagsSection(beliefs: beliefs)
                            .padding(.horizontal, 20)
                    }

                    // 8. Claim button (unclaimed only, flag-gated inside FindChurch2ClaimButton)
                    FindChurch2ClaimButton(church: church)
                        .padding(.horizontal, 20)

                    Spacer(minLength: 12)
                }
                .padding(.bottom, 20)
            }
            .safeAreaInset(edge: .bottom) {
                SaveShareFooter(churchName: church.name)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
            .navigationTitle(church.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(.title3))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close church profile")
                }
            }
        }
        // Apply the spring animation to the entire sheet presentation.
        // matchedGeometryEffect is applied to the church name Text inside headerSection.
        .animation(reduceMotion ? .none : .spring(response: 0.45, dampingFraction: 0.82), value: cardId)
    }

    // MARK: - Header section

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Church name — matchedGeometryEffect anchor
            Group {
                if reduceMotion {
                    Text(church.name)
                        .font(.system(.largeTitle).weight(.bold))
                        .foregroundStyle(.primary)
                } else {
                    Text(church.name)
                        .font(.system(.largeTitle).weight(.bold))
                        .foregroundStyle(.primary)
                        .matchedGeometryEffect(id: cardId, in: namespace)
                }
            }
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)

            // Address
            Text(church.address)
                .font(.system(.subheadline))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            // City + state
            if !church.city.isEmpty {
                Text("\(church.city)\(church.state.map { ", \($0)" } ?? "")")
                    .font(.system(.subheadline))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - Community signals section

    @ViewBuilder
    private var communitySignalsSection: some View {
        let signals = FindChurch2CommunitySignals(
            church: church,
            friendSavedCount: church.friendSavedCount
        )
        // AvatarCluster for member count
        if church.amenMemberCount > 0 {
            VStack(alignment: .leading, spacing: 10) {
                FindChurch2AvatarCluster(count: church.amenMemberCount, maxVisible: 3)
                    .padding(.horizontal, 20)
                signals
                    .padding(.horizontal, 20)
            }
        } else {
            signals
                .padding(.horizontal, 20)
        }
    }

    // MARK: - Visit planner section

    private var visitPlannerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Plan Your Visit")
                .padding(.horizontal, 20)

            FindChurch2VisitPlannerView(
                church: church,
                availability: availability,
                comfortPrefs: comfortPrefs
            )
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Concierge section

    private var conciergeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Ask About This Church")
                .padding(.horizontal, 20)

            FindChurch2ConciergeView(church: church)
                .padding(.horizontal, 20)
        }
    }
}

// MARK: - FindChurch2CardToProfileTransition

/// `ViewModifier` applied to `FindChurch2SmartChurchCard`.
/// Adds tap-to-expand behavior that opens `FindChurch2ChurchProfileSheet`.
///
/// Usage:
/// ```swift
/// FindChurch2SmartChurchCard(...)
///     .modifier(FindChurch2CardToProfileTransition(
///         church: church,
///         match: match,
///         availability: availability,
///         comfortPrefs: comfortPrefs,
///         namespace: namespace
///     ))
/// ```
struct FindChurch2CardToProfileTransition: ViewModifier {

    // MARK: Interface

    let church: ChurchObject
    let match: MatchExplanation?
    let availability: AvailabilityStatus
    let comfortPrefs: [SeekerProfile.ComfortChip]
    var namespace: Namespace.ID

    // MARK: State

    @State private var showProfile: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    func body(content: Content) -> some View {
        content
            .onTapGesture {
                showProfile = true
            }
            .accessibilityAction(named: Text("View church profile")) {
                showProfile = true
            }
            .sheet(isPresented: $showProfile) {
                FindChurch2ChurchProfileSheet(
                    church: church,
                    match: match,
                    availability: availability,
                    comfortPrefs: comfortPrefs,
                    namespace: namespace,
                    cardId: church.id
                )
            }
    }
}

// MARK: - Convenience extension on SmartChurchCard

extension View {
    /// Attaches card → profile sheet expansion to any `FindChurch2SmartChurchCard`.
    func findChurch2ProfileExpansion(
        church: ChurchObject,
        match: MatchExplanation?,
        availability: AvailabilityStatus,
        comfortPrefs: [SeekerProfile.ComfortChip],
        namespace: Namespace.ID
    ) -> some View {
        self.modifier(FindChurch2CardToProfileTransition(
            church: church,
            match: match,
            availability: availability,
            comfortPrefs: comfortPrefs,
            namespace: namespace
        ))
    }
}

// MARK: - Previews

#if DEBUG
private let _profilePreviewChurch = ChurchObject(
    id: "profile-preview-1",
    placeId: nil,
    ein: nil,
    name: "Hillside Community Church",
    normalizedName: "hillside community church",
    address: "789 Hillside Blvd",
    normalizedAddress: "789 hillside blvd",
    city: "Phoenix",
    state: "AZ",
    zipCode: "85001",
    country: "US",
    coordinate: .init(latitude: 33.4484, longitude: -112.0740),
    phoneNumber: "(602) 555-0199",
    email: "info@hillside.example.com",
    website: "https://hillside.example.com",
    photoURL: nil,
    logoURL: nil,
    denomination: "Non-denominational",
    denominationFamily: nil,
    denominationIsFlexible: true,
    denominationLineage: [],
    beliefs: BeliefSchema(
        baptismView: "believer's baptism",
        communionView: "memorial",
        governance: "congregational",
        worshipStyle: "contemporary",
        spiritualGifts: "open",
        womenInMinistry: "egalitarian",
        scriptureView: "inerrancy",
        customTags: ["Expository preaching"]
    ),
    serviceTimes: [
        StructuredServiceTime(
            dayOfWeek: 1,
            startHour: 9,
            startMinute: 0,
            durationMinutes: 75,
            serviceType: "First Service",
            isAccessibleASL: true,
            isAccessibleWheelchair: true
        ),
        StructuredServiceTime(
            dayOfWeek: 1,
            startHour: 11,
            startMinute: 0,
            durationMinutes: 75,
            serviceType: "Main Service"
        )
    ],
    mediaLinks: .init(detectedMediaType: .youtube),
    accessibility: .init(
        hasASL: true,
        isWheelchairAccessible: true,
        languages: ["en", "es"],
        hasChildcare: true,
        parkingNotes: "Free lot behind the building",
        entranceNotes: "Accessible ramp on north side"
    ),
    claimState: .verified,
    verificationTier: .ein,
    claimedBy: "uid-123",
    claimedAt: Date(),
    childSafetyPolicy: .init(hasFormalPolicy: true, backgroundChecksRequired: true, policyURL: nil),
    staffCount: 6,
    ministryTags: ["youth", "women", "recovery"],
    gatheringIds: ["g1", "g2", "g3"],
    availabilityCache: nil,
    availabilityCachedAt: nil,
    pendingServiceTimeSuggestions: 0,
    amenMemberCount: 142,
    visitCount: 380,
    friendSavedCount: 7,
    source: .googlePlaces,
    createdAt: Date(),
    updatedAt: Date(),
    isDeleted: false
)

private let _profilePreviewAvailability = AvailabilityStatus(
    openNow: false,
    serviceToday: true,
    serviceTime: "9:00 AM",
    studyTonight: false,
    livestreamActive: true,
    prayerAvailable: false,
    contactNeeded: false,
    computedAt: Date()
)

private let _profilePreviewMatch = MatchExplanation(
    score: 88,
    topReasons: [
        .init(category: .distance, label: "0.8 mi away", weight: 0.95, isPositive: true),
        .init(category: .worshipStyle, label: "Contemporary worship", weight: 0.85, isPositive: true)
    ],
    mismatches: [],
    generatedBy: "local",
    generatedAt: Date()
)

#Preview("Profile Sheet — full church") {
    @Previewable @Namespace var ns
    FindChurch2ChurchProfileSheet(
        church: _profilePreviewChurch,
        match: _profilePreviewMatch,
        availability: _profilePreviewAvailability,
        comfortPrefs: [.needChildcare, .showParking],
        namespace: ns,
        cardId: _profilePreviewChurch.id
    )
}

#Preview("Card + Transition Modifier") {
    @Previewable @Namespace var ns
    ScrollView {
        FindChurch2SmartChurchCard(
            church: _profilePreviewChurch,
            match: _profilePreviewMatch,
            intent: .visitSunday,
            availability: _profilePreviewAvailability,
            showMatchExplain: true
        )
        .findChurch2ProfileExpansion(
            church: _profilePreviewChurch,
            match: _profilePreviewMatch,
            availability: _profilePreviewAvailability,
            comfortPrefs: [.needChildcare],
            namespace: ns
        )
        .padding()
    }
}
#endif
