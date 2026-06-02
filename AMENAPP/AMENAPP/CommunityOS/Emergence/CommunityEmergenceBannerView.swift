// CommunityEmergenceBannerView.swift
// AMEN App — Community Around Content OS
//
// Floating banner that surfaces when a new community forms around content.
// Also contains GrowingCommunitiesView for the list surface.

import SwiftUI
import Foundation

// MARK: - Formatted Member Count

private extension Int {
    /// Formats an integer as "1.2K" for thousands, "1.1M" for millions, etc.
    var formattedMemberCount: String {
        switch self {
        case 0:
            return "0 members"
        case 1:
            return "1 member"
        case 2..<1_000:
            return "\(self) members"
        case 1_000..<1_000_000:
            let value = Double(self) / 1_000.0
            let formatted = value.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0fK", value)
                : String(format: "%.1fK", value)
            return "\(formatted) members"
        default:
            let value = Double(self) / 1_000_000.0
            let formatted = value.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0fM", value)
                : String(format: "%.1fM", value)
            return "\(formatted) members"
        }
    }
}

// MARK: - CommunityEmergenceBannerView

/// Floating card that slides in from the top when a new community auto-emerges.
/// Automatically dismisses after 8 seconds.
struct CommunityEmergenceBannerView: View {

    let node: CommunityNode
    let onJoin: () -> Void
    let onDismiss: () -> Void

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            bannerCard
        }
        .transition(
            .asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)
            )
        )
        .onAppear {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            scheduleAutoDismiss()
        }
        // VoiceOver: treat the whole banner as a single interactive region.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityBannerLabel)
        .accessibilityAddTraits(.isModal)
    }

    // MARK: Card

    private var bannerCard: some View {
        HStack(alignment: .top, spacing: 12) {
            // Kind icon
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 44, height: 44)
                Image(systemName: node.contentKind.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Color(.label))
                    .accessibilityHidden(true)
            }

            // Text column
            VStack(alignment: .leading, spacing: 4) {
                Text("New Community Formed")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(Color(.secondaryLabel))
                    .textCase(.uppercase)
                    .tracking(0.4)

                Text(node.name)
                    .font(.headline)
                    .foregroundColor(Color(.label))
                    .lineLimit(2)

                Text("A new community formed around this \(node.contentKind.displayName.lowercased())")
                    .font(.subheadline)
                    .foregroundColor(Color(.secondaryLabel))
                    .lineLimit(2)

                Text(node.memberCount.formattedMemberCount)
                    .font(.caption)
                    .foregroundColor(Color(.secondaryLabel))
                    .padding(.top, 2)

                // Join button — Liquid Glass only on the button itself
                Button(action: {
                    onJoin()
                    onDismiss()
                }) {
                    Text("Join Community")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(Color(.label))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .glassEffect()
                .padding(.top, 6)
                .accessibilityLabel("Join \(node.name)")
                .accessibilityHint("Joins this community and closes this notification")
            }

            Spacer(minLength: 0)

            // Dismiss button
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(.secondaryLabel))
                    .padding(8)
                    .background(Color(.tertiarySystemBackground), in: Circle())
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: Auto-dismiss

    private func scheduleAutoDismiss() {
        Task {
            try? await Task.sleep(for: .seconds(8))
            onDismiss()
        }
    }

    // MARK: Accessibility

    private var accessibilityBannerLabel: String {
        "New community: \(node.name). \(node.memberCount.formattedMemberCount). " +
        "A new community formed around this \(node.contentKind.displayName.lowercased()). " +
        "Double tap to join."
    }
}

// MARK: - CommunityCardView

/// A single community card used inside GrowingCommunitiesView.
private struct CommunityCardView: View {

    let node: CommunityNode
    let onJoin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top row: icon + name + member badge
            HStack(alignment: .top, spacing: 12) {
                // Kind icon circle
                ZStack {
                    Circle()
                        .fill(Color(.secondarySystemBackground))
                        .frame(width: 48, height: 48)
                    Image(systemName: node.contentKind.systemImage)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(Color(.label))
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(node.name)
                        .font(.headline)
                        .foregroundColor(Color(.label))
                        .lineLimit(2)
                    Text(node.contentKind.displayName)
                        .font(.caption)
                        .foregroundColor(Color(.secondaryLabel))
                }

                Spacer()

                // Member count badge — no follower/like vanity metrics
                Text(node.memberCount.formattedMemberCount)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(Color(.secondaryLabel))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.tertiarySystemBackground), in: Capsule())
            }

            // Activity stats — discussions and prayers only (no vanity counts)
            HStack(spacing: 16) {
                activityStat(
                    icon: CommunityLayer.discussion.systemImage,
                    label: "\(node.discussionCount) discussions"
                )
                activityStat(
                    icon: CommunityLayer.prayer.systemImage,
                    label: "\(node.prayerCount) prayers"
                )
            }

            // Active layers chips
            if !node.activeLayers.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(node.activeLayers, id: \.self) { layer in
                            layerChip(layer)
                        }
                    }
                }
            }

            // Join button
            Button(action: onJoin) {
                HStack(spacing: 6) {
                    Image(systemName: "person.badge.plus")
                        .font(.subheadline)
                    Text("Join")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(Color(.label))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .glassEffect()
            .accessibilityLabel("Join \(node.name)")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 2)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(node.name), \(node.contentKind.displayName), \(node.memberCount.formattedMemberCount), \(node.discussionCount) discussions, \(node.prayerCount) prayers")
    }

    private func activityStat(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(Color(.secondaryLabel))
                .accessibilityHidden(true)
            Text(label)
                .font(.caption)
                .foregroundColor(Color(.secondaryLabel))
        }
    }

    private func layerChip(_ layer: CommunityLayer) -> some View {
        HStack(spacing: 3) {
            Image(systemName: layer.systemImage)
                .font(.system(size: 9, weight: .medium))
                .accessibilityHidden(true)
            Text(layer.displayName)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(Color(.secondaryLabel))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.secondarySystemBackground), in: Capsule())
    }
}

// MARK: - GrowingCommunitiesView

/// A vertically scrollable list of community cards.
/// Labeled "Growing Communities" — never "Trending."
/// Shows no follower counts or like counts.
struct GrowingCommunitiesView: View {

    let communities: [CommunityNode]
    let onJoin: (CommunityNode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            Text("Growing Communities")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(Color(.label))
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 12)
                .accessibilityAddTraits(.isHeader)

            if communities.isEmpty {
                emptyState
            } else {
                communitiesList
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: List

    private var communitiesList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 12) {
                ForEach(communities) { node in
                    CommunityCardView(node: node) {
                        onJoin(node)
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 24)
        }
        .accessibilityLabel("Growing Communities list, \(communities.count) communities")
    }

    // MARK: Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            // Illustration placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 120, height: 120)
                Image(systemName: "person.3.fill")
                    .font(.system(size: 44))
                    .foregroundColor(Color(.tertiaryLabel))
                    .accessibilityHidden(true)
            }

            VStack(spacing: 8) {
                Text("No Communities Yet")
                    .font(.headline)
                    .foregroundColor(Color(.label))
                Text("Communities form when people engage with content together. Keep exploring — something is growing.")
                    .font(.subheadline)
                    .foregroundColor(Color(.secondaryLabel))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.bottom, 40)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No communities yet. Communities form when people engage with content together.")
    }
}

// MARK: - Preview Support

#if DEBUG
private extension CommunityNode {
    static func preview(
        name: String,
        kind: ContentObjectKind,
        memberCount: Int,
        discussions: Int,
        prayers: Int,
        layers: [CommunityLayer]
    ) -> CommunityNode {
        CommunityNode(
            id: UUID().uuidString,
            contentObjectId: UUID().uuidString,
            contentKind: kind,
            name: name,
            memberCount: memberCount,
            discussionCount: discussions,
            prayerCount: prayers,
            isAutoGenerated: true,
            activeLayers: layers
        )
    }
}

#Preview("Emergence Banner") {
    ZStack(alignment: .top) {
        Color(.systemGroupedBackground).ignoresSafeArea()
        CommunityEmergenceBannerView(
            node: .preview(
                name: "Oceans Community",
                kind: .song,
                memberCount: 1_247,
                discussions: 340,
                prayers: 82,
                layers: [.worship, .discussion, .reflection]
            ),
            onJoin: {},
            onDismiss: {}
        )
        .padding(.top, 60)
    }
}

#Preview("Growing Communities — Populated") {
    GrowingCommunitiesView(
        communities: [
            .preview(
                name: "Oceans Community",
                kind: .song,
                memberCount: 1_247,
                discussions: 340,
                prayers: 82,
                layers: [.worship, .discussion, .reflection]
            ),
            .preview(
                name: "Romans 8:28 Community",
                kind: .bibleVerse,
                memberCount: 3_891,
                discussions: 720,
                prayers: 510,
                layers: [.study, .prayer, .reflection, .discussion]
            ),
            .preview(
                name: "The Case for Christ Readers",
                kind: .book,
                memberCount: 567,
                discussions: 203,
                prayers: 44,
                layers: [.study, .discussion, .reflection, .mentorship]
            ),
            .preview(
                name: "Louie Giglio — Indescribable Study Community",
                kind: .sermon,
                memberCount: 12_800,
                discussions: 1_430,
                prayers: 980,
                layers: [.discussion, .study, .reflection, .prayer]
            )
        ],
        onJoin: { _ in }
    )
}

#Preview("Growing Communities — Empty") {
    GrowingCommunitiesView(communities: [], onJoin: { _ in })
}
#endif
