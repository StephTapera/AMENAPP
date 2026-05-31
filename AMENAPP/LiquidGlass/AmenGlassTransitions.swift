import SwiftUI

// MARK: - Hero Transition Helpers
// matchedGeometryEffect wrappers for card → detail hero transitions.
//
// Usage — in the common ancestor view:
//   @Namespace private var heroNamespace
//
// On the source (e.g. PostCard thumbnail):
//   .amenGlassHeroSource(id: post.id, namespace: heroNamespace)
//
// On the destination (e.g. AmenMediaDetailView):
//   .amenGlassHeroDestination(id: post.id, namespace: heroNamespace)
//
// SwiftUI interpolates geometry between the two; wrap the transition in
// Motion.adaptive(.spring(...)) on a withAnimation call at the presentation site.

extension View {
    /// Marks this view as a hero transition source.
    func amenGlassHeroSource(id: some Hashable, namespace: Namespace.ID) -> some View {
        matchedGeometryEffect(id: id, in: namespace, isSource: true)
    }

    /// Marks this view as the hero transition destination.
    func amenGlassHeroDestination(id: some Hashable, namespace: Namespace.ID) -> some View {
        matchedGeometryEffect(id: id, in: namespace, isSource: false)
    }
}

// MARK: - AmenGlassComposerExpansion
// Animates a composer bar between pill (collapsed) and full panel (expanded)
// by morphing the clip shape corner radius.
// Use this on the container view; toggle `isExpanded` to drive the transition.
// The motion profile is read from the environment — set it with `.amenSmartSheet`
// or `.environment(\.amenMotionProfile, .action)` on a parent.

private struct AmenGlassComposerExpansionModifier: ViewModifier {
    let isExpanded: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .clipShape(
                RoundedRectangle(
                    cornerRadius: isExpanded
                        ? LiquidGlassTokens.cornerRadiusMedium
                        : LiquidGlassTokens.capsuleRadius,
                    style: .continuous
                )
            )
            .animation(
                reduceMotion
                    ? .easeOut(duration: LiquidGlassTokens.motionFast)
                    : .spring(response: 0.32, dampingFraction: 0.82),
                value: isExpanded
            )
    }
}

extension View {
    /// Morphs the clip shape from pill → rounded rect as a composer expands.
    func amenGlassComposerExpansion(isExpanded: Bool) -> some View {
        modifier(AmenGlassComposerExpansionModifier(isExpanded: isExpanded))
    }
}

// MARK: - AmenGlassTabContextual
// Overlays a contextual action bar on top of the existing tab bar content
// when `isContextual` is true. Slides up from the bottom with spring motion;
// includes a dismiss button that fires `onDismiss`.
//
// Usage (in ContentView or any root coordinator):
//   contentStack
//       .amenGlassTabContextual(
//           isContextual: isSelectingMedia,
//           items: [
//               AmenGlassTabContextualItem(icon: "photo", label: "Photo") { ... },
//               AmenGlassTabContextualItem(icon: "video", label: "Video") { ... },
//           ],
//           onDismiss: { isSelectingMedia = false }
//       )

struct AmenGlassTabContextualItem: Identifiable {
    let id: String
    let icon: String
    let label: String
    let action: () -> Void

    init(
        id: String = UUID().uuidString,
        icon: String,
        label: String,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.icon = icon
        self.label = label
        self.action = action
    }
}

private struct AmenGlassTabContextualModifier: ViewModifier {
    let isContextual: Bool
    let contextualItems: [AmenGlassTabContextualItem]
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        ZStack(alignment: .bottom) {
            content

            if isContextual {
                contextualBar
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .move(edge: .bottom))
                    )
                    .zIndex(10)
            }
        }
        .animation(
            reduceMotion
                ? .easeOut(duration: LiquidGlassTokens.motionFast)
                : .spring(response: 0.32, dampingFraction: 0.82),
            value: isContextual
        )
    }

    private var contextualBar: some View {
        HStack(spacing: 0) {
            ForEach(contextualItems) { item in
                Button(action: item.action) {
                    VStack(spacing: 4) {
                        Image(systemName: item.icon)
                            .font(.system(size: 20, weight: .medium))
                        Text(item.label)
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.label)
            }

            Button(action: onDismiss) {
                VStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20, weight: .medium))
                    Text("Done")
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(.secondary)
                .frame(width: 60)
                .frame(height: 54)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss contextual actions")
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
        .background { barBackground }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var barBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(.systemBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        } else {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LiquidGlassTokens.blurElevated)
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.32), lineWidth: 0.7)
                }
                .shadow(color: .black.opacity(0.22), radius: 22, y: 10)
        }
    }
}

extension View {
    /// Overlays a glass contextual action bar at the bottom when `isContextual` is true.
    /// The bar slides up over (not replacing) the normal tab bar.
    func amenGlassTabContextual(
        isContextual: Bool,
        items: [AmenGlassTabContextualItem],
        onDismiss: @escaping () -> Void
    ) -> some View {
        modifier(AmenGlassTabContextualModifier(
            isContextual: isContextual,
            contextualItems: items,
            onDismiss: onDismiss
        ))
    }
}

// MARK: - AmenGlassScrollAwareOpacity
// Subtly compresses and fades a floating bar (tab bar, header, etc.) as the
// user scrolls down. Reads a scroll offset preference key value piped in from
// the calling view.
//
// Usage:
//   AMENTabBar(...)
//       .amenGlassScrollAware(scrollOffset: feedScrollOffset)
//
// Provide `scrollOffset` as positive-when-scrolled-down. The modifier clips
// compression at `collapseThreshold` to avoid over-dimming.

private struct AmenGlassScrollAwareOpacityModifier: ViewModifier {
    let scrollOffset: CGFloat
    var collapseThreshold: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var progress: CGFloat {
        guard collapseThreshold > 0 else { return 0 }
        return min(1, max(0, scrollOffset / collapseThreshold))
    }

    func body(content: Content) -> some View {
        content
            .opacity(1.0 - progress * 0.12)
            .scaleEffect(y: 1.0 - progress * 0.04, anchor: .bottom)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.08),
                value: progress
            )
    }
}

extension View {
    /// Fades and compresses a bar as the user scrolls down.
    /// `scrollOffset` must be positive when scrolled down, zero at top.
    func amenGlassScrollAware(
        scrollOffset: CGFloat,
        collapseThreshold: CGFloat = 80
    ) -> some View {
        modifier(AmenGlassScrollAwareOpacityModifier(
            scrollOffset: scrollOffset,
            collapseThreshold: collapseThreshold
        ))
    }
}
