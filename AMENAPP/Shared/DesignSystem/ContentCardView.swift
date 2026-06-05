// ContentCardView.swift
// AMENAPP — Shared/DesignSystem
//
// Renders a ContentCard with its allowed-action control row.
// Uses the existing ContentCard / ContentAction / ContentPermissionEngine types.

import SwiftUI

// MARK: - Content Card View

struct ContentCardView: View {
    let card: ContentCard
    let availableActions: [ContentAction]
    let onAction: (ContentAction) -> Void

    @State private var showShareSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            if !card.body.isEmpty { bodyPreview }
            audienceRow
            if !availableActions.isEmpty {
                Divider().opacity(0.4)
                actionRow
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .confirmationDialog("Share or Discuss", isPresented: $showShareSheet) {
            ForEach(availableActions.prefix(6), id: \.self) { action in
                Button(action.displayName) { onAction(action) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: card.sourceType.icon)
                .font(.subheadline)
                .foregroundStyle(Color.amenGold)
            Text(card.title)
                .font(.headline)
                .lineLimit(2)
            Spacer()
            if card.sensitivityScore > 0.4 || card.hasPrayerContent || card.hasMinors {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Sensitive content")
            }
        }
    }

    @ViewBuilder
    private var bodyPreview: some View {
        Text(card.body)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(3)
    }

    private var audienceRow: some View {
        HStack(spacing: 4) {
            Image(systemName: audienceIcon)
                .font(.caption)
            Text(card.originalAudience.displayName)
                .font(.caption)
        }
        .foregroundStyle(.tertiary)
    }

    private var actionRow: some View {
        HStack(spacing: 20) {
            CardActionButton(icon: "bubble.left", label: "Discuss") { showShareSheet = true }
            CardActionButton(icon: "square.and.arrow.up", label: "Share")  { showShareSheet = true }
            CardActionButton(icon: "bookmark", label: "Save") { onAction(.saveToChurchNotes) }
            Spacer()
        }
    }

    private var audienceIcon: String {
        switch card.originalAudience {
        case .private:       return "lock.fill"
        case .trustedCircle: return "person.3.fill"
        case .smallGroup:    return "person.2.fill"
        case .churchOnly:    return "building.columns.fill"
        case .spaceMembers:  return "rectangle.3.group.fill"
        case .paidMembers:   return "star.fill"
        case .publicFeed:    return "globe"
        }
    }
}

// MARK: - Action Button

private struct CardActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption)
                Text(label).font(.caption)
            }
            .foregroundStyle(Color.amenGold)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Preview

#Preview {
    ContentCardView(
        card: ContentCard(
            id: "preview-1",
            title: "Sunday Sermon Reflection",
            body: "God's grace is sufficient for all our needs. This sermon really spoke to me about trusting in His timing.",
            sourceType: .sermonClip,
            sourceSurface: .amenConnect,
            sourceId: "sermon-123",
            originalAudience: .spaceMembers,
            creatorId: "user-1",
            creatorDisplayName: "Pastor James",
            sensitivityScore: 0.2,
            hasPrayerContent: false,
            hasChildContent: false,
            hasLocationData: false,
            hasMinors: false,
            isAnonymous: false,
            isPaidContent: false,
            isDM: false,
            isChurchInternal: false,
            createdAt: Date(),
            expiresAt: nil,
            moderationState: .safe,
            discussionStatus: .open,
            attributionRules: ContentAttributionRules(
                requiresAttribution: true,
                allowsAnonymous: false,
                allowsQuoteOnly: false,
                expiresAfterDays: nil
            )
        ),
        availableActions: [.discussInSpace, .saveToChurchNotes, .createStudy],
        onAction: { _ in }
    )
    .padding()
}
