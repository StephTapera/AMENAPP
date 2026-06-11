// FindChurch2CommunitySignalsView.swift
// AMENAPP — Find Church 2.0, Wave 6
//
// Community-signal chips and avatar cluster for church profiles.
// Design rules (HARD — do not relax):
//   - Glass: .ultraThinMaterial only — no nested materials, no custom opacity stacks
//   - Luminous border: Color.white.opacity(0.45) strokeBorder 0.5 pt
//   - No vanity metrics: no like counts, no follower counts, ever
//   - Allowed signals: amenMemberCount, friendSavedCount, gatheringIds, accessibility
//   - All tap targets ≥ 44×44 pt (chips are display-only; no tap targets required here)
//   - Dynamic Type text styles only — no fixed point sizes
//   - @Environment(\.accessibilityReduceTransparency) guards glass backgrounds
//   - EmptyView when all signals are false/zero — caller decides whether to show
//
// Wave: 6 | Depends: FindChurch2Contracts.swift

import SwiftUI
import Foundation

// MARK: - SignalChip (private)

/// A single glass pill chip showing an SF Symbol + label text.
private struct SignalChip: View {
    let symbol: String
    let label: String

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(.caption2).weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(label)
                .font(.system(.caption2).weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(chipBackground)
        .overlay(chipBorder)
        .clipShape(Capsule(style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var chipBackground: some View {
        if reduceTransparency {
            Capsule(style: .continuous)
                .fill(Color(.secondarySystemBackground))
        } else {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }

    private var chipBorder: some View {
        Capsule(style: .continuous)
            .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5)
    }
}

// MARK: - FindChurch2AvatarCluster

/// Stacked placeholder avatar circles representing AMEN member count.
/// Shows up to `maxVisible` letter-initial circles, then "+N more" overflow text.
/// Returns EmptyView when count is zero.
struct FindChurch2AvatarCluster: View {

    let count: Int
    var maxVisible: Int = 3

    private let avatarSize: CGFloat = 26
    private let overlap: CGFloat = 8

    private var visibleCount: Int {
        min(count, maxVisible)
    }

    private var overflowCount: Int {
        max(0, count - maxVisible)
    }

    // Stable placeholder initials for stacked circles
    private let placeholderInitials: [String] = ["A", "M", "E", "N", "B", "C"]

    var body: some View {
        if count == 0 {
            EmptyView()
        } else {
            HStack(spacing: 6) {
                stackedAvatars
                if overflowCount > 0 {
                    Text("+\(overflowCount) more")
                        .font(.system(.caption2))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(count) AMEN member\(count == 1 ? "" : "s") attend this church")
        }
    }

    private var stackedAvatars: some View {
        HStack(spacing: -(overlap)) {
            ForEach(0..<visibleCount, id: \.self) { index in
                avatarCircle(initial: placeholderInitials[index % placeholderInitials.count])
                    // Bring later circles to front with zIndex so overlap stacks left-to-right
                    .zIndex(Double(visibleCount - index))
            }
        }
    }

    private func avatarCircle(initial: String) -> some View {
        ZStack {
            Circle()
                .fill(Color(.tertiarySystemBackground))
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.55), lineWidth: 1.0)
                )
            Text(initial)
                .font(.system(.caption2).weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: avatarSize, height: avatarSize)
    }
}

// MARK: - FindChurch2CommunitySignals

/// Horizontal flow of community-signal chips.
///
/// Renders only signals that are present (> 0 or true). When all signals
/// evaluate to zero/false this view renders `EmptyView()` — the caller
/// is responsible for deciding whether to show the section header.
///
/// Permitted signals:
///   - "{N} AMEN members attend"   (amenMemberCount > 0)
///   - "{N} friends saved this"    (friendSavedCount > 0)
///   - "Active Bible study"        (gatheringIds.count > 0)
///   - "New-visitor friendly"      (hasChildcare OR hasASL)
///
/// NEVER shows: like counts, follower counts, or any vanity metric.
struct FindChurch2CommunitySignals: View {

    let church: ChurchObject
    let friendSavedCount: Int

    // MARK: - Signal resolution

    private struct Signal: Identifiable {
        let id = UUID()
        let symbol: String
        let label: String
    }

    private var activeSignals: [Signal] {
        var signals: [Signal] = []

        if church.amenMemberCount > 0 {
            let formatted = formattedCount(church.amenMemberCount)
            signals.append(Signal(
                symbol: "person.2.fill",
                label: "\(formatted) AMEN member\(church.amenMemberCount == 1 ? "" : "s") attend"
            ))
        }

        if friendSavedCount > 0 {
            signals.append(Signal(
                symbol: "person.badge.plus",
                label: "\(friendSavedCount) friend\(friendSavedCount == 1 ? "" : "s") saved this"
            ))
        }

        if church.gatheringIds.count > 0 {
            signals.append(Signal(
                symbol: "book.fill",
                label: "Active Bible study"
            ))
        }

        if church.accessibility.hasChildcare || church.accessibility.hasASL {
            signals.append(Signal(
                symbol: "figure.walk.arrival",
                label: "New-visitor friendly"
            ))
        }

        return signals
    }

    // MARK: - Body

    var body: some View {
        if activeSignals.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(activeSignals) { signal in
                        SignalChip(symbol: signal.symbol, label: signal.label)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
            .accessibilityElement(children: .contain)
        }
    }

    // MARK: - Helpers

    private func formattedCount(_ count: Int) -> String {
        count >= 1000
            ? String(format: "%.1fk", Double(count) / 1000.0)
            : "\(count)"
    }
}

// MARK: - Previews

#if DEBUG
private let _communityPreviewChurch = ChurchObject(
    id: "community-preview-1",
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
    mediaLinks: .init(detectedMediaType: .none),
    accessibility: .init(hasASL: true, hasChildcare: true),
    claimState: .verified,
    verificationTier: .domain,
    claimedBy: nil,
    claimedAt: nil,
    childSafetyPolicy: .init(),
    staffCount: nil,
    ministryTags: [],
    gatheringIds: ["g1", "g2"],
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

#Preview("Community Signals — full") {
    VStack(spacing: 24) {
        FindChurch2CommunitySignals(church: _communityPreviewChurch, friendSavedCount: 5)
            .padding()

        FindChurch2AvatarCluster(count: 142, maxVisible: 3)
            .padding()
    }
}

#Preview("Community Signals — empty") {
    let emptyChurch = ChurchObject(
        id: "community-preview-empty",
        placeId: nil,
        ein: nil,
        name: "New Life",
        normalizedName: "new life",
        address: "456 Oak Ave",
        normalizedAddress: "456 oak ave",
        city: "Phoenix",
        state: "AZ",
        zipCode: "85001",
        country: "US",
        coordinate: .init(latitude: 33.4484, longitude: -112.0740),
        phoneNumber: nil,
        email: nil,
        website: nil,
        photoURL: nil,
        logoURL: nil,
        denomination: nil,
        denominationFamily: nil,
        denominationIsFlexible: true,
        denominationLineage: [],
        beliefs: nil,
        serviceTimes: [],
        mediaLinks: .init(detectedMediaType: .none),
        accessibility: .init(),
        claimState: .unclaimed,
        verificationTier: .none,
        claimedBy: nil,
        claimedAt: nil,
        childSafetyPolicy: .init(),
        staffCount: nil,
        ministryTags: [],
        gatheringIds: [],
        availabilityCache: nil,
        availabilityCachedAt: nil,
        pendingServiceTimeSuggestions: 0,
        amenMemberCount: 0,
        visitCount: 0,
        friendSavedCount: 0,
        source: .userSubmitted,
        createdAt: Date(),
        updatedAt: Date(),
        isDeleted: false
    )

    // EmptyView — nothing rendered, intentional
    VStack {
        Text("(empty — all signals zero)")
            .font(.system(.caption))
            .foregroundStyle(.secondary)
        FindChurch2CommunitySignals(church: emptyChurch, friendSavedCount: 0)
    }
    .padding()
}

#Preview("Avatar Cluster — overflow") {
    VStack(spacing: 16) {
        FindChurch2AvatarCluster(count: 7, maxVisible: 3)
        FindChurch2AvatarCluster(count: 2, maxVisible: 3)
        FindChurch2AvatarCluster(count: 0, maxVisible: 3) // EmptyView
    }
    .padding()
}
#endif
