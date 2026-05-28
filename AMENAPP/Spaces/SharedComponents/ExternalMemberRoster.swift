// ExternalMemberRoster.swift
// AMENAPP — Spaces v2 Shared Components (Agent C)
//
// Member sheet that sections external members under their home community.
// CONTRACT_C public API name — delegates to MemberRosterSheet internally.
// Import this — B/D/E/F never re-implement.
// See CONTRACT_C.md for the full API.

import SwiftUI

/// Member sheet component that sections external members under their home community.
/// Renders own-community members first ("Members"), then one section per external community.
/// Each external section header shows the community name + LinkedCommunityGlyph.
///
/// Usage:
/// ```swift
/// ExternalMemberRoster(
///     members: spaceMembers,
///     communityNames: ["comm_xyz": "Hillside Community"]
/// )
/// ```
struct ExternalMemberRoster: View {

    // MARK: - Parameters (CONTRACT_C public API)

    let members: [SpaceMember]
    /// communityId → display name. Used to resolve homeCommunityId for section headers.
    let communityNames: [String: String]

    // MARK: - Computed sections

    private var localMembers: [SpaceMember] {
        members.filter { $0.homeCommunityId.isEmpty }
    }

    private var externalGroups: [(communityId: String, name: String, members: [SpaceMember])] {
        var grouped: [String: [SpaceMember]] = [:]
        for member in members where !member.homeCommunityId.isEmpty {
            grouped[member.homeCommunityId, default: []].append(member)
        }
        return grouped
            .map { (
                communityId: $0.key,
                name: communityNames[$0.key] ?? $0.key,
                members: $0.value
            ) }
            .sorted { $0.communityId < $1.communityId }
    }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // Section: own-community members
                if !localMembers.isEmpty {
                    sectionHeader("Members")
                    ForEach(localMembers) { member in
                        RosterRow(member: member, isExternal: false)
                    }
                }

                // Sections: one per external community
                ForEach(externalGroups, id: \.communityId) { group in
                    externalSectionHeader(
                        communityId: group.communityId,
                        displayName: group.name
                    )
                    ForEach(group.members) { member in
                        RosterRow(member: member, isExternal: true)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Section headers

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(AmenTheme.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 16)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func externalSectionHeader(communityId: String, displayName: String) -> some View {
        HStack(spacing: 6) {
            LinkedCommunityGlyph(size: 14, communityName: displayName)
                .accessibilityHidden(true)
            Text(displayName)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.top, 16)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("External members from \(displayName)")
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Roster Row

private struct RosterRow: View {
    let member: SpaceMember
    let isExternal: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(AmenTheme.Colors.surfaceChip)
                    .frame(width: 40, height: 40)
                    .overlay {
                        Text((member.id ?? member.homeCommunityId).prefix(1).uppercased())
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                    }

                if isExternal {
                    LinkedCommunityGlyph(size: 10, communityName: member.homeCommunityId)
                        .offset(x: 4, y: 4)
                        .accessibilityHidden(true)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(member.id ?? "member")
                    .font(.subheadline)
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .lineLimit(1)
                Text(member.role.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }

            Spacer(minLength: 0)

            if member.access == .none {
                Text("Access revoked")
                    .font(.caption2)
                    .foregroundStyle(AmenTheme.Colors.statusError)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(member.id ?? "member"), \(member.role.rawValue)\(isExternal ? ", external member" : "")")
    }
}

#if DEBUG
#Preview("ExternalMemberRoster") {
    let sample: [SpaceMember] = [
        SpaceMember(role: .owner, homeCommunityId: "", access: .granted, joinedAt: Timestamp(date: .now)),
        SpaceMember(role: .member, homeCommunityId: "", access: .granted, joinedAt: Timestamp(date: .now)),
        SpaceMember(role: .member, homeCommunityId: "comm_xyz", access: .granted, joinedAt: Timestamp(date: .now)),
        SpaceMember(role: .member, homeCommunityId: "comm_abc", access: .none, joinedAt: Timestamp(date: .now)),
    ]
    ExternalMemberRoster(
        members: sample,
        communityNames: [
            "comm_xyz": "Hillside Community",
            "comm_abc": "Grace Fellowship"
        ]
    )
}
#endif
