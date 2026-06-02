// AmenMinistryRoomHeaderView.swift
// AMEN Connect + Spaces — Living Ministry Rooms
// Agent 3 — built 2026-06-01

import SwiftUI

// MARK: - Room Type Color & Label Helpers

private extension AmenConnectSpacesRoomType {
    var displayName: String {
        switch self {
        case .smallGroup:     return "Small Group"
        case .prayer:         return "Prayer"
        case .worship:        return "Worship"
        case .missions:       return "Missions"
        case .staff:          return "Staff"
        case .cohort:         return "Cohort"
        case .accountability: return "Accountability"
        }
    }

    var icon: String {
        switch self {
        case .smallGroup:     return "person.3"
        case .prayer:         return "hands.sparkles"
        case .worship:        return "music.note"
        case .missions:       return "globe.americas"
        case .staff:          return "briefcase"
        case .cohort:         return "rectangle.3.group"
        case .accountability: return "shield.lefthalf.filled"
        }
    }

    /// Badge tint — each type gets a distinct amenGold/amenPurple/amenBlue tint
    var badgeColor: Color {
        switch self {
        case .smallGroup:     return Color(red: 0.431, green: 0.294, blue: 0.710) // amenPurple
        case .prayer:         return Color(red: 0.851, green: 0.643, blue: 0.255) // amenGold
        case .worship:        return Color(red: 0.851, green: 0.643, blue: 0.255) // amenGold (warm)
        case .missions:       return Color(red: 0.141, green: 0.357, blue: 0.561) // amenBlue
        case .staff:          return Color(red: 0.141, green: 0.357, blue: 0.561) // amenBlue
        case .cohort:         return Color(red: 0.431, green: 0.294, blue: 0.710) // amenPurple
        case .accountability: return Color(red: 0.851, green: 0.643, blue: 0.255) // amenGold
        }
    }
}

// MARK: - Header View

struct AmenMinistryRoomHeaderView: View {
    let space: AmenConnectSpacesSpace

    @State private var descriptionExpanded: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                // Room name — matte, large title
                Text(space.name)
                    .font(.system(size: 20, weight: .bold, design: .default))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 4)

                // Room type badge (glass pill)
                roomTypeBadge
            }

            // Member count — no public engagement metrics
            HStack(spacing: 4) {
                Image(systemName: "person.2")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("\(space.memberIds.count) member\(space.memberIds.count == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(space.memberIds.count) members")

            // Collapsible description (matte)
            if descriptionExpanded {
                descriptionArea
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Expand toggle
            Button {
                let anim: Animation = reduceMotion
                    ? .easeInOut(duration: 0.01)
                    : .easeInOut(duration: 0.22)
                withAnimation(anim) {
                    descriptionExpanded.toggle()
                }
            } label: {
                HStack(spacing: 3) {
                    Text(descriptionExpanded ? "Less" : "About this room")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(space.type.badgeColor)
                    Image(systemName: descriptionExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(space.type.badgeColor)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(descriptionExpanded ? "Collapse room description" : "Expand room description")
        }
    }

    // MARK: - Type Badge

    private var roomTypeBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: space.type.icon)
                .font(.system(size: 10, weight: .semibold))
            Text(space.type.displayName)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(space.type.badgeColor)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background {
            Capsule()
                .fill(space.type.badgeColor.opacity(0.15))
                .overlay {
                    Capsule()
                        .strokeBorder(space.type.badgeColor.opacity(0.35), lineWidth: 1)
                }
        }
        .accessibilityLabel("Room type: \(space.type.displayName)")
    }

    // MARK: - Description (matte)

    private var descriptionArea: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Room Details")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

            Text("Created \(space.createdAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            if space.careSensitivity {
                HStack(spacing: 5) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.851, green: 0.643, blue: 0.255))
                    Text("Care-sensitive space")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("This is a care-sensitive space")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.102, green: 0.086, blue: 0.118))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                }
        )
    }
}
