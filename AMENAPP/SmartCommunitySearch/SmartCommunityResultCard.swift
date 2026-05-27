import SwiftUI

struct SmartCommunityResultCard: View {
    let result: SmartCommunityRankedResult
    let onAction: (SmartCommunityAction) -> Void
    let onAskBerean: (SmartCommunityRankedResult) -> Void

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var isSaved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row: icon, title, type badge, match label
            headerRow

            // Subtitle
            if let subtitle = result.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Distance + Match label
            HStack(spacing: 8) {
                if let distance = result.distanceLabel {
                    Label(distance, systemImage: "location.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                matchBadge
            }

            // Reasons
            if !result.reasons.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(result.reasons.prefix(2), id: \.self) { reason in
                        Label(reason, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }

            // Cautions
            if let cautions = result.cautions, !cautions.isEmpty {
                ForEach(cautions.prefix(1), id: \.self) { caution in
                    Label(caution, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            // Tags
            if !result.tags.isEmpty {
                tagRow
            }

            Divider()

            // Action buttons row - ALL WIRED
            actionRow
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(result.title), \(result.type.rawValue), \(result.matchLabel)")
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 10) {
            typeIconView
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let subtitle = result.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
    }

    private var typeIconView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(typeColor.opacity(0.15))
                .frame(width: 40, height: 40)
            Image(systemName: typeIcon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(typeColor)
        }
    }

    private var matchBadge: some View {
        Text(result.matchLabel)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(matchColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(matchColor.opacity(0.12), in: Capsule())
    }

    private var tagRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(result.tags.prefix(5), id: \.self) { tag in
                    Text(tag)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray6), in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            // Primary action
            if let primary = result.primaryAction {
                Button {
                    onAction(primary)
                } label: {
                    Text(primary.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .accessibilityLabel(primary.label)
            }

            // Save button
            Button {
                isSaved.toggle()
                if let saveAction = result.action(ofType: .save) {
                    onAction(saveAction)
                }
            } label: {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 18))
                    .foregroundStyle(isSaved ? .yellow : .secondary)
                    .frame(width: 40, height: 40)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .accessibilityLabel(isSaved ? "Unsave" : "Save")

            // Directions button
            if result.action(ofType: .directions) != nil || result.locationCoord != nil {
                Button {
                    if let directionsAction = result.action(ofType: .directions) {
                        onAction(directionsAction)
                    }
                } label: {
                    Image(systemName: "arrow.triangle.turn.up.right.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .accessibilityLabel("Get directions")
            }

            // Ask Berean
            Button {
                onAskBerean(result)
            } label: {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .accessibilityLabel("Ask Berean about this community")
        }
    }

    // MARK: - Helpers

    private var typeIcon: String {
        switch result.type {
        case .church: return "building.columns.fill"
        case .space: return "rectangle.3.group.fill"
        case .group: return "person.3.fill"
        case .event: return "calendar.badge.plus"
        case .discussion: return "bubble.left.and.bubble.right.fill"
        case .creator: return "person.wave.2.fill"
        case .mentor: return "person.badge.shield.checkmark.fill"
        }
    }

    private var typeColor: Color {
        switch result.type {
        case .church: return .blue
        case .space: return .purple
        case .group: return .green
        case .event: return .orange
        case .discussion: return .teal
        case .creator: return .pink
        case .mentor: return .indigo
        }
    }

    private var matchColor: Color {
        if result.matchScore > 0.75 { return .green }
        if result.matchScore > 0.5 { return .orange }
        return .secondary
    }
}
