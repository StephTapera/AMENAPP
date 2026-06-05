// AmenProgressiveHeroView.swift
// AMEN App — Community OS › Hero Experience
//
// Phase 5 Agent D2 — Hero Experience
// A card that starts compact and expands to a large immersive hero when tapped.
//
// Collapsed state:  AmenHeroHeader at .compact height (200pt), inside AmenCard white surface
// Expanded state:   AmenHeroHeader at .large height (360pt), full-width, overlaid above content
//
// Animation: spring matchedGeometryEffect between the two states.
// accessibilityReduceMotion: animation is replaced with a simple opacity transition when true.
//
// Design contract (C3):
//   - Collapsed card: white fill + AmenShadow.card + AmenRadius.card (28pt)
//   - Expanded overlay: .large hero bleeds under status bar (.ignoresSafeArea(.all, edges: .top))
//   - Dismiss: swipe-down gesture OR tap-outside region OR X pill button
//   - Badge pill + text: AmenGlassDarkPill pattern (black.opacity(0.55), white text)
//   - NO custom hex colors — system semantics + AmenDesignSystem tokens only
//   - All interactive targets: minimum 44x44pt

import SwiftUI

// MARK: — AmenProgressiveHeroView

/// A hero card that expands from a compact card to a full-screen immersive
/// overlay when the user taps it.
///
/// In the expanded state the hero occupies the full screen width and bleeds
/// under the status bar. A dismiss pill is shown at the bottom.
/// The parent content remains in place beneath the expanded overlay.
///
/// Usage:
/// ```swift
/// AmenProgressiveHeroView(
///     imageUrl: sermon.coverImageUrl,
///     title: "Faith Over Fear",
///     subtitle: "Pastor James",
///     badge: "Sermon"
/// )
/// ```
struct AmenProgressiveHeroView: View {

    let imageUrl: String?
    let title: String
    let subtitle: String?
    let badge: String?

    // MARK: - State

    @State private var isExpanded = false
    @Namespace private var heroNamespace

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        ZStack {
            // Collapsed card — always in the layout flow
            if !isExpanded {
                collapsedCard
                    .matchedGeometryEffect(id: "hero-photo", in: heroNamespace)
            } else {
                // Invisible placeholder preserving layout space
                Color.clear
                    .frame(height: AmenHeroHeader.HeroHeight.compact.points)
            }
        }
        .overlay {
            // Expanded overlay — rendered in the view tree but full-screen
            if isExpanded {
                expandedOverlay
            }
        }
    }

    // MARK: - Collapsed card

    private var collapsedCard: some View {
        Button {
            expand()
        } label: {
            AmenHeroHeader(
                imageUrl: imageUrl,
                title: title,
                subtitle: subtitle,
                badge: badge,
                height: .compact
            ) {
                // Expand hint icon
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle().fill(Color.black.opacity(0.55))
                    )
                    .overlay(
                        Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                    )
                    .padding(.trailing, 10)
                    .padding(.bottom, 10)
            }
        }
        .buttonStyle(.plain)
        .amenCard()
        .contentShape(RoundedRectangle(cornerRadius: AmenRadius.card, style: .continuous))
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double-tap to expand")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Expanded overlay

    private var expandedOverlay: some View {
        ZStack(alignment: .bottom) {

            // Dim background behind the expanded hero
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { collapse() }
                .transition(.opacity)

            // Large hero + dismiss pill
            VStack(spacing: 0) {
                AmenHeroHeader(
                    imageUrl: imageUrl,
                    title: title,
                    subtitle: subtitle,
                    badge: badge,
                    height: .large
                ) {
                    EmptyView()
                }
                .matchedGeometryEffect(id: "hero-photo", in: heroNamespace)
                .ignoresSafeArea(.all, edges: .top)

                // Dismiss pill
                dismissPill
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                    .background(Color.white)
            }
            .clipShape(RoundedRectangle(cornerRadius: AmenRadius.card, style: .continuous))
            .shadow(
                color: Color.black.opacity(AmenShadow.floating.opacity),
                radius: AmenShadow.floating.radius,
                x: AmenShadow.floating.x,
                y: AmenShadow.floating.y
            )
            .padding(.horizontal, 12)
            .transition(
                reduceMotion
                    ? .opacity
                    : .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
            )
            .gesture(
                DragGesture(minimumDistance: 40)
                    .onEnded { value in
                        // Swipe-down to dismiss
                        if value.translation.height > 80 {
                            collapse()
                        }
                    }
            )
        }
    }

    // MARK: - Dismiss pill

    private var dismissPill: some View {
        Button {
            collapse()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                Text("Close")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Color(uiColor: .label))
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color(uiColor: .secondarySystemFill))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Collapse hero")
        .accessibilityHint("Tap to collapse")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Animation helpers

    private func expand() {
        if reduceMotion {
            isExpanded = true
        } else {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.80)) {
                isExpanded = true
            }
        }
    }

    private func collapse() {
        if reduceMotion {
            isExpanded = false
        } else {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                isExpanded = false
            }
        }
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        var parts = [title]
        if let subtitle { parts.append(subtitle) }
        if let badge { parts.append(badge) }
        return parts.joined(separator: ", ")
    }
}

// MARK: — Preview

#if DEBUG
#Preview("Progressive Hero — collapsed") {
    ScrollView {
        VStack(spacing: 20) {
            AmenProgressiveHeroView(
                imageUrl: nil,
                title: "Faith Over Fear",
                subtitle: "Pastor James · 42 min",
                badge: "Sermon"
            )

            AmenProgressiveHeroView(
                imageUrl: nil,
                title: "Young Adult Night",
                subtitle: "Crosspoint Church",
                badge: "Event"
            )

            // Filler to prove the overlay sits above scroll content
            ForEach(0..<10, id: \.self) { i in
                Text("Content row \(i + 1)")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(20)
    }
    .background(Color(uiColor: .systemGroupedBackground))
}
#endif
