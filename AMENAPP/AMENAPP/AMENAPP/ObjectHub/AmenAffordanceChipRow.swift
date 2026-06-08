import SwiftUI

// MARK: - Affordance Chip Row
// The above-the-fold relationship affordances required by the build pack thesis:
// every content detail screen must expose at least one "join people" affordance above the fold.
// Displays Discussion · Prayer Room · Study Group as tappable chips with live participant counts.

struct AmenAffordanceChipRow: View {
    let affordances: [ObjectAffordance]
    let onTap: (ObjectAffordance) -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(affordances) { affordance in
                    AffordanceChip(
                        affordance: affordance,
                        reduceTransparency: reduceTransparency,
                        reduceMotion: reduceMotion,
                        onTap: { onTap(affordance) }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Community rooms for this content")
    }
}

// MARK: - Single Chip

private struct AffordanceChip: View {
    let affordance: ObjectAffordance
    let reduceTransparency: Bool
    let reduceMotion: Bool
    let onTap: () -> Void

    @State private var isPressed = false

    private var accentColor: Color {
        switch affordance.kind {
        case .discussion:     return .blue
        case .prayerRoom:     return .purple
        case .studyGroup:     return .green
        case .membersPresent: return .teal
        case .liveNow:        return .red
        }
    }

    private var icon: String {
        switch affordance.kind {
        case .discussion:     return "bubble.left.and.bubble.right.fill"
        case .prayerRoom:     return "hands.sparkles.fill"
        case .studyGroup:     return "book.fill"
        case .membersPresent: return "person.2.fill"
        case .liveNow:        return "dot.radiowaves.left.and.right"
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                // Icon
                Image(systemName: icon)
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(accentColor)

                // Label
                VStack(alignment: .leading, spacing: 1) {
                    Text(affordance.label)
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(.primary)

                    Group {
                        if affordance.spawnable {
                            Text("Tap to start")
                                .font(.systemScaled(11))
                                .foregroundStyle(.secondary)
                        } else if affordance.participantCount > 0 {
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                                Text("\(affordance.participantCount) inside")
                                    .font(.systemScaled(11))
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Tap to join")
                                .font(.systemScaled(11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Spawn indicator
                if affordance.spawnable {
                    Image(systemName: "plus.circle.fill")
                        .font(.systemScaled(14))
                        .foregroundStyle(accentColor.opacity(0.7))
                } else {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.systemScaled(14))
                        .foregroundStyle(accentColor.opacity(0.7))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(chipBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(accentColor.opacity(affordance.isLive ? 0.5 : 0.2), lineWidth: 1)
            )
            .scaleEffect(isPressed && !reduceMotion ? 0.96 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !reduceMotion else { return }
                    withAnimation(.easeIn(duration: 0.08)) { isPressed = true }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isPressed = false }
                }
        )
        .accessibilityLabel(affordance.accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var chipBackground: some ShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
        }
        return AnyShapeStyle(.ultraThinMaterial)
    }
}

// MARK: - Loading Placeholder

struct AmenAffordanceChipRowSkeleton: View {
    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { _ in
                Capsule()
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 120, height: 44)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .accessibilityLabel("Loading community rooms")
        .accessibilityHidden(true)
    }
}
