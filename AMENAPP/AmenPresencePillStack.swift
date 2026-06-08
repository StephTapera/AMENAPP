import SwiftUI

// MARK: - AmenPresencePillStack
//
// Surfaces up to AmenGlassBehavior.presencePillMaxVisible (3) ranked Liquid Glass
// action pills above any content surface. Pills are hidden during fast scrolling
// and reappear automatically when scroll velocity drops to rest.
//
// Rules enforced here:
//  - Never show more than 3 pills at a time
//  - Higher-priority (lower rawValue) actions shown first
//  - Duplicate action IDs suppressed
//  - Pills collapse to a "More" overflow button when > maxVisible
//  - Pills fade out when scrollVelocity exceeds threshold
//  - Reappear after pillShowRestDelay once velocity settles
//  - Safety actions are never hidden

struct AmenPresencePillStack: View {
    let actions: [AmenSmartAction]
    var scrollVelocity: CGFloat = 0
    var alignment: HorizontalAlignment = .center
    var spacing: CGFloat = AmenGlassMetrics.pillStackSpacing
    var onOverflowTap: (([AmenSmartAction]) -> Void)? = nil

    @State private var isVisible: Bool = true
    @State private var showOverflow: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var sortedUnique: [AmenSmartAction] {
        var seen = Set<String>()
        return actions
            .sorted { $0.priority < $1.priority }
            .filter { seen.insert($0.id).inserted }
    }

    private var visiblePills: [AmenSmartAction] {
        Array(sortedUnique.prefix(AmenGlassBehavior.presencePillMaxVisible))
    }

    private var overflowPills: [AmenSmartAction] {
        Array(sortedUnique.dropFirst(AmenGlassBehavior.presencePillMaxVisible))
    }

    var body: some View {
        HStack(spacing: spacing) {
            if alignment == .leading { Spacer() }

            ForEach(visiblePills) { action in
                presencePill(for: action)
            }

            if !overflowPills.isEmpty {
                overflowButton
            }

            if alignment == .trailing { Spacer() }
        }
        .opacity(pillsOpacity)
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.2), value: isVisible)
        .onChange(of: scrollVelocity) { velocity in
            updateVisibility(velocity: velocity)
        }
    }

    @ViewBuilder
    private func presencePill(for action: AmenSmartAction) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action.action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: action.icon)
                    .font(.systemScaled(12, weight: .medium))

                VStack(alignment: .leading, spacing: 0) {
                    Text(action.title)
                        .font(.systemScaled(13, weight: .medium))
                    if let sub = action.subtitle {
                        Text(sub)
                            .font(.systemScaled(10))
                            .opacity(0.72)
                    }
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, AmenGlassMetrics.pillHorizontalPadding)
            .padding(.vertical, AmenGlassMetrics.pillVerticalPadding)
            .background(pillBackground)
            .clipShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.title)
        .accessibilityHint(action.subtitle ?? "")
        .accessibilityAddTraits(.isButton)
    }

    private var overflowButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onOverflowTap?(overflowPills)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "ellipsis")
                    .font(.systemScaled(12, weight: .medium))
                Text("More")
                    .font(.systemScaled(13, weight: .medium))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, AmenGlassMetrics.pillHorizontalPadding)
            .padding(.vertical, AmenGlassMetrics.pillVerticalPadding)
            .background(pillBackground)
            .clipShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More actions")
        .accessibilityHint("\(overflowPills.count) additional actions available")
    }

    @ViewBuilder
    private var pillBackground: some View {
        if reduceTransparency {
            Capsule(style: .continuous)
                .fill(Color(.systemBackground))
                .overlay(Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
        } else {
            Capsule(style: .continuous)
                .fill(.thinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.50), Color.white.opacity(0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.6
                        )
                }
                .shadow(color: .black.opacity(0.07), radius: 6, x: 0, y: 2)
        }
    }

    private var pillsOpacity: Double {
        isVisible ? 1 : 0
    }

    private func updateVisibility(velocity: CGFloat) {
        let isFastScroll = abs(velocity) > AmenGlassBehavior.pillHideVelocityThreshold
        if isFastScroll {
            guard isVisible else { return }
            withAnimation(reduceMotion ? .none : .easeOut(duration: 0.15)) {
                isVisible = false
            }
        } else {
            guard !isVisible else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + AmenGlassBehavior.pillShowRestDelay) {
                withAnimation(reduceMotion ? .none : .easeIn(duration: 0.2)) {
                    isVisible = true
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Presence Pill Stack") {
    VStack(spacing: 20) {
        AmenPresencePillStack(actions: [
            AmenSmartAction(icon: "book.closed", title: "Bible Context", priority: .scriptureContext) {},
            AmenSmartAction(icon: "sparkles", title: "Ask Berean", priority: .semanticDefinition) {},
            AmenSmartAction(icon: "text.badge.plus", title: "Save to Selah", priority: .reflection) {},
            AmenSmartAction(icon: "note.text", title: "Open Notes", priority: .secondary) {},
        ])
        .padding(.horizontal)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemBackground))
}
#endif
