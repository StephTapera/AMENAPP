// MemberRosterSheet.swift
// AMENAPP — Spaces v2 Shared Components (Agent C)
//
// Bottom sheet listing Space members, external members SECTIONED under their
// homeCommunityId. Driven by [SpaceMember] — no additional Firestore reads.
// Import this — never re-implement. See CONTRACT_C.md for full API.

import SwiftUI

/// Bottom sheet listing Space members, external members SECTIONED under their
/// homeCommunityId. Driven by [SpaceMember] — no additional Firestore reads.
/// Import this — never re-implement.
struct MemberRosterSheet: View {

    let members: [SpaceMember]
    /// The owning community — members with homeCommunityId == nil or matching this
    /// appear in the primary "Members" section. Others are grouped by their external
    /// homeCommunityId.
    let localCommunityId: String
    @Binding var isPresented: Bool
    /// Caller provides this map to resolve homeCommunityId → display name.
    var communityNames: CommunityNameMap = [:]

    // MARK: - Computed sections

    private var localMembers: [SpaceMember] {
        members.filter { m in
            m.homeCommunityId == nil || m.homeCommunityId == localCommunityId
        }
    }

    private var externalGroups: [(communityId: String, members: [SpaceMember])] {
        let externals = members.filter { m in
            guard let hcid = m.homeCommunityId else { return false }
            return hcid != localCommunityId
        }
        var grouped: [String: [SpaceMember]] = [:]
        for m in externals {
            guard let hcid = m.homeCommunityId else { continue }
            grouped[hcid, default: []].append(m)
        }
        return grouped
            .map { (communityId: $0.key, members: $0.value) }
            .sorted { $0.communityId < $1.communityId }
    }

    var body: some View {
        AmenLiquidGlassBottomSheet(
            title: "Members",
            subtitle: "\(members.count) \(members.count == 1 ? "member" : "members")",
            aiDisclosure: nil,
            content: {
                VStack(alignment: .leading, spacing: 0) {
                    // Section 1: owning-community members
                    if !localMembers.isEmpty {
                        sectionHeader(title: "Members")
                        ForEach(localMembers) { member in
                            MemberRow(
                                member: member,
                                isExternal: false,
                                communityNames: communityNames
                            )
                        }
                    }

                    // Section 2+: one section per external community
                    ForEach(externalGroups, id: \.communityId) { group in
                        let displayName = communityNames[group.communityId] ?? group.communityId
                        externalSectionHeader(communityId: group.communityId, displayName: displayName)
                        ForEach(group.members) { member in
                            MemberRow(
                                member: member,
                                isExternal: true,
                                communityNames: communityNames
                            )
                        }
                    }
                }
            },
            footer: {
                Button {
                    isPresented = false
                } label: {
                    Text("Done")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(AmenTheme.Colors.surfaceChip)
                        .clipShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Done")
                .accessibilityHint("Closes the members sheet.")
            }
        )
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Section header views

    @ViewBuilder
    private func sectionHeader(title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(AmenTheme.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func externalSectionHeader(communityId: String, displayName: String) -> some View {
        HStack(spacing: 6) {
            LinkedGlyph(size: .small)
            Text(displayName)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("External members from \(displayName)")
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - CommunityNameMap extension

extension MemberRosterSheet {
    /// Caller provides this map to resolve homeCommunityId → display name.
    typealias CommunityNameMap = [String: String]
}

// MARK: - MemberRow

private struct MemberRow: View {
    let member: SpaceMember
    let isExternal: Bool
    let communityNames: MemberRosterSheet.CommunityNameMap

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(AmenTheme.Colors.surfaceChip)
                    .frame(width: 40, height: 40)
                    .overlay {
                        Text(member.userId.prefix(1).uppercased())
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                    }

                if isExternal {
                    LinkedGlyph(size: .small)
                        .offset(x: 4, y: 4)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(member.userId)
                    .font(.subheadline)
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .lineLimit(1)

                Text(member.role.capitalized)
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
        .accessibilityLabel("\(member.userId), \(member.role)\(isExternal ? ", external member" : "")")
    }
}

#if DEBUG
#Preview("MemberRosterSheet") {
    @Previewable @State var isPresented = true

    let sample: [SpaceMember] = [
        SpaceMember(userId: "alice", role: "owner", homeCommunityId: nil,
                    access: .granted, joinedAt: nil),
        SpaceMember(userId: "bob", role: "member", homeCommunityId: nil,
                    access: .granted, joinedAt: nil),
        SpaceMember(userId: "carol", role: "member", homeCommunityId: "community_xyz",
                    access: .granted, joinedAt: nil),
        SpaceMember(userId: "dave", role: "guest", homeCommunityId: "community_xyz",
                    access: .none, joinedAt: nil),
        SpaceMember(userId: "eve", role: "member", homeCommunityId: "community_abc",
                    access: .granted, joinedAt: nil),
    ]

    Text("Tap to show sheet")
        .sheet(isPresented: $isPresented) {
            MemberRosterSheet(
                members: sample,
                localCommunityId: "community_local",
                isPresented: $isPresented,
                communityNames: [
                    "community_xyz": "Hillside Community",
                    "community_abc": "Grace Fellowship"
                ]
            )
        }
}
#endif
