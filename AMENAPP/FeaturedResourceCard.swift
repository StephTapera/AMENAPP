// FeaturedResourceCard.swift
// AMENAPP
//
// Premium featured destination cards for the Grow and Platform sections
// of ResourcesView.
//
// Design language: inspired by the reference card's hierarchy —
//   upper-left hero visual · small category label · large title · metadata row
// — but reinterpreted through AMEN's spiritual, minimal, editorial identity.
//
// Components:
//   FeaturedResourceCard      — configurable base card (reusable)
//   GrowFeaturedCard          — Grow / Walk With Christ hero card
//   PlatformFeaturedCard      — Platform / Build & Serve hero card
//   GrowHeroVisual            — abstract leaf-light motif (Grow)
//   PlatformHeroVisual        — abstract grid-beacon motif (Platform)
//   FeaturedCardMetaItem      — single icon + label metadata chip
//   FeaturedCardPressStyle    — button style wiring press → card lift

import SwiftUI

// MARK: - Design tokens (scoped to this file)

private enum FeaturedCardTokens {
    // Card geometry
    static let cornerRadius: CGFloat = 22
    static let height: CGFloat       = 160
    static let hPad: CGFloat         = 18
    static let vPad: CGFloat         = 16

    // Typography
    static let categoryFont = Font.system(size: 10, weight: .semibold, design: .default)
    static let titleFont    = Font.system(size: 24, weight: .bold,    design: .default)
    static let metaFont     = Font.system(size: 11, weight: .medium,  design: .default)
}

// MARK: - FeaturedResourceCard (base)

/// Generic featured card. Pass any SwiftUI view as the `heroVisual`.
/// All typography/layout constants come from FeaturedCardTokens.
struct FeaturedResourceCard<HeroVisual: View>: View {

    /// Short all-caps category marker (e.g. "GROW", "PLATFORM")
    let category: String
    /// Large bold title
    let title: String
    /// Bottom-row metadata items (icon + label pairs)
    let metaItems: [MetaItem]
    /// Card surface gradient — left edge to right edge
    let cardGradient: LinearGradient
    /// Category label color
    let categoryColor: Color
    /// Hero visual rendered top-left
    @ViewBuilder let heroVisual: () -> HeroVisual

    struct MetaItem: Identifiable {
        let id = UUID()
        let icon: String
        let label: String
    }

    // Press animation
    @State private var isPressed = false

    var body: some View {
        ZStack(alignment: .topLeading) {

            // ── Card surface ────────────────────────────────────────────────
            RoundedRectangle(cornerRadius: FeaturedCardTokens.cornerRadius, style: .continuous)
                .fill(cardGradient)

            // Soft top-edge glass sheen
            RoundedRectangle(cornerRadius: FeaturedCardTokens.cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.18), .clear],
                        startPoint: .top,
                        endPoint: .init(x: 0.5, y: 0.38)
                    )
                )

            // Subtle border
            RoundedRectangle(cornerRadius: FeaturedCardTokens.cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.30), .white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )

            // ── Hero visual — upper-left, large, dimensional ────────────────
            heroVisual()
                .frame(width: 88, height: 88)
                .padding(.top, FeaturedCardTokens.vPad - 4)
                .padding(.leading, FeaturedCardTokens.hPad - 4)

            // ── Text content — anchored bottom-left ─────────────────────────
            VStack(alignment: .leading, spacing: 4) {
                Spacer()

                // Category label
                Text(category)
                    .font(FeaturedCardTokens.categoryFont)
                    .foregroundStyle(categoryColor)
                    .kerning(1.2)

                // Hero title
                Text(title)
                    .font(FeaturedCardTokens.titleFont)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                // Metadata row
                HStack(spacing: 14) {
                    ForEach(metaItems) { item in
                        FeaturedCardMetaItem(icon: item.icon, label: item.label)
                    }
                    Spacer()
                    // Chevron hint
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, FeaturedCardTokens.hPad)
            .padding(.bottom, FeaturedCardTokens.vPad)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(maxWidth: .infinity)
        .frame(height: FeaturedCardTokens.height)
        // Layered shadow — soft ambient glow + ground shadow
        .shadow(color: shadowColor.opacity(0.28), radius: isPressed ? 8 : 20, x: 0, y: isPressed ? 3 : 10)
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        // Press lift/compress
        .scaleEffect(isPressed ? 0.974 : 1.0)
        .offset(y: isPressed ? 2 : 0)
        .animation(.spring(response: 0.30, dampingFraction: 0.72), value: isPressed)
        // Accessibility
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(category): \(title)")
        .accessibilityHint("Tap to explore")
        .accessibilityAddTraits(.isButton)
    }

    // Shadow matches the card's dominant color so the glow feels intentional
    private var shadowColor: Color {
        // Extract from gradient start by checking the category string
        // We pass it in from the concrete card types below
        categoryColor
    }
}

// MARK: - Metadata chip

private struct FeaturedCardMetaItem: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            Text(label)
                .font(FeaturedCardTokens.metaFont)
                .foregroundStyle(.white.opacity(0.65))
        }
    }
}

// MARK: - GrowFeaturedCard

/// Hero card for the Grow section.
/// Visual identity: warm amber-ochre — warmth, wisdom, upward growth.
/// Hero motif: soft stacked leaf-light shapes — organic, upward, scripture-rooted.
struct GrowFeaturedCard: View {
    var body: some View {
        FeaturedResourceCard(
            category: "GROW",
            title: "Walk With Christ",
            metaItems: [
                .init(icon: "book.pages", label: "Devotionals"),
                .init(icon: "chart.line.uptrend.xyaxis", label: "Milestones"),
                .init(icon: "sun.horizon", label: "Daily habits"),
            ],
            cardGradient: LinearGradient(
                stops: [
                    .init(color: Color(red: 0.72, green: 0.38, blue: 0.10), location: 0.0),
                    .init(color: Color(red: 0.55, green: 0.26, blue: 0.06), location: 0.6),
                    .init(color: Color(red: 0.40, green: 0.18, blue: 0.04), location: 1.0),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            categoryColor: Color(red: 1.0, green: 0.80, blue: 0.45)
        ) {
            GrowHeroVisual()
        }
    }
}

// MARK: - PlatformFeaturedCard

/// Hero card for the Platform section.
/// Visual identity: deep indigo-slate — purpose, structure, aspiration, calling.
/// Hero motif: abstract beacon grid — visibility, building, vocation.
struct PlatformFeaturedCard: View {
    var body: some View {
        FeaturedResourceCard(
            category: "PLATFORM",
            title: "Build & Serve",
            metaItems: [
                .init(icon: "person.2.wave.2", label: "Mentorship"),
                .init(icon: "briefcase",       label: "Jobs"),
                .init(icon: "pencil.and.ruler", label: "Creator"),
            ],
            cardGradient: LinearGradient(
                stops: [
                    .init(color: Color(red: 0.18, green: 0.22, blue: 0.52), location: 0.0),
                    .init(color: Color(red: 0.12, green: 0.14, blue: 0.40), location: 0.55),
                    .init(color: Color(red: 0.08, green: 0.08, blue: 0.28), location: 1.0),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            categoryColor: Color(red: 0.68, green: 0.72, blue: 1.0)
        ) {
            PlatformHeroVisual()
        }
    }
}

// MARK: - GrowHeroVisual

/// Abstract organic visual for the Grow card.
/// Three overlapping leaf-like ellipses — warm amber → gold → cream.
/// Rendered purely in SwiftUI shapes; no external assets required.
struct GrowHeroVisual: View {
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Back leaf — largest, deepest amber
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.98, green: 0.64, blue: 0.18).opacity(0.90),
                            Color(red: 0.85, green: 0.42, blue: 0.08).opacity(0.70),
                        ],
                        center: .init(x: 0.35, y: 0.35),
                        startRadius: 0,
                        endRadius: 55
                    )
                )
                .frame(width: 88, height: 70)
                .rotationEffect(.degrees(-28))
                .offset(x: -4, y: 6)
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1.0 : 0.6)
                .animation(
                    reduceMotion ? .none : .spring(response: 0.55, dampingFraction: 0.70).delay(0.06),
                    value: appeared
                )

            // Middle leaf — narrower, brighter gold
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.0, green: 0.80, blue: 0.28).opacity(0.95),
                            Color(red: 0.95, green: 0.55, blue: 0.12).opacity(0.75),
                        ],
                        center: .init(x: 0.40, y: 0.30),
                        startRadius: 0,
                        endRadius: 42
                    )
                )
                .frame(width: 60, height: 80)
                .rotationEffect(.degrees(8))
                .offset(x: 8, y: -4)
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1.0 : 0.5)
                .animation(
                    reduceMotion ? .none : .spring(response: 0.52, dampingFraction: 0.68).delay(0.12),
                    value: appeared
                )

            // Front accent — small, bright cream near top
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.0, green: 0.95, blue: 0.70).opacity(0.95),
                            Color(red: 1.0, green: 0.78, blue: 0.30).opacity(0.60),
                        ],
                        center: .init(x: 0.45, y: 0.35),
                        startRadius: 0,
                        endRadius: 28
                    )
                )
                .frame(width: 38, height: 52)
                .rotationEffect(.degrees(-10))
                .offset(x: 16, y: -18)
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1.0 : 0.4)
                .animation(
                    reduceMotion ? .none : .spring(response: 0.48, dampingFraction: 0.66).delay(0.20),
                    value: appeared
                )

            // Subtle soft glow bloom at base — grounds the shapes
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 1.0, green: 0.72, blue: 0.20).opacity(0.32), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 48
                    )
                )
                .frame(width: 96, height: 40)
                .offset(y: 28)
                .blur(radius: 8)
                .opacity(appeared ? 1 : 0)
                .animation(
                    reduceMotion ? .none : .easeOut(duration: 0.60).delay(0.10),
                    value: appeared
                )
        }
        .onAppear { appeared = true }
        .accessibilityHidden(true)
    }
}

// MARK: - PlatformHeroVisual

/// Abstract geometric visual for the Platform card.
/// A 3×3 dot grid with a soft beacon glow — suggests structure, visibility, calling.
/// Rendered purely in SwiftUI; no external assets required.
struct PlatformHeroVisual: View {
    @State private var appeared = false
    @State private var glowPhase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Grid configuration
    private let dotSize: CGFloat  = 7
    private let dotSpacing: CGFloat = 20
    private let rows = 3
    private let cols = 3

    var body: some View {
        ZStack {
            // Soft ambient background circle
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.46, green: 0.52, blue: 1.0).opacity(0.30),
                            .clear,
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 52
                    )
                )
                .frame(width: 110, height: 110)
                .blur(radius: 12)
                .opacity(appeared ? 1 : 0)
                .animation(
                    reduceMotion ? .none : .easeOut(duration: 0.55),
                    value: appeared
                )

            // 3×3 dot grid
            VStack(spacing: dotSpacing) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: dotSpacing) {
                        ForEach(0..<cols, id: \.self) { col in
                            dotView(row: row, col: col)
                        }
                    }
                }
            }

            // Central beacon highlight — larger bright dot at grid center
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.82, green: 0.86, blue: 1.0),
                            Color(red: 0.50, green: 0.56, blue: 0.96),
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 10
                    )
                )
                .frame(width: 16, height: 16)
                .shadow(color: Color(red: 0.58, green: 0.64, blue: 1.0).opacity(0.80), radius: 8)
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1.0 : 0.2)
                .animation(
                    reduceMotion ? .none : .spring(response: 0.50, dampingFraction: 0.65).delay(0.18),
                    value: appeared
                )

            // Pulsing beacon ring (subtle, loop only if motion allowed)
            if !reduceMotion {
                Circle()
                    .stroke(Color(red: 0.70, green: 0.76, blue: 1.0).opacity(0.35 - glowPhase * 0.35), lineWidth: 1.2)
                    .frame(width: 34 + glowPhase * 18, height: 34 + glowPhase * 18)
                    .opacity(appeared ? 1 : 0)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                            glowPhase = 1.0
                        }
                    }
            }
        }
        .onAppear { appeared = true }
        .accessibilityHidden(true)
    }

    private func dotView(row: Int, col: Int) -> some View {
        let distFromCenter = sqrt(pow(Double(row - 1), 2) + pow(Double(col - 1), 2))
        let delay = distFromCenter * 0.08 + 0.05
        // Dots farther from center are slightly smaller and dimmer
        let scale = row == 1 && col == 1 ? 0.0 : 1.0   // center replaced by beacon above
        let opacity = 0.50 + (1.0 - distFromCenter / 2.0) * 0.35
        let dotColor = Color(
            red: 0.55 + Double(cols - col) * 0.05,
            green: 0.60 + Double(col) * 0.04,
            blue: 0.96
        )

        return Circle()
            .fill(dotColor.opacity(opacity))
            .frame(width: dotSize * CGFloat(scale == 0 ? 0 : 1),
                   height: dotSize * CGFloat(scale == 0 ? 0 : 1))
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1.0 : 0.0)
            .animation(
                reduceMotion ? .none : .spring(response: 0.44, dampingFraction: 0.68).delay(delay),
                value: appeared
            )
    }
}

// MARK: - FeaturedCardPressStyle

/// ButtonStyle that routes press state into any child that reads
/// it via environment — used with NavigationLink wrappers.
/// Also applies a direct scale since FeaturedResourceCard self-animates.
struct FeaturedCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.974 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.70), value: configuration.isPressed)
    }
}

// MARK: - Previews

#Preview("Grow Card") {
    GrowFeaturedCard()
        .padding(20)
        .background(Color(.systemGroupedBackground))
}

#Preview("Platform Card") {
    PlatformFeaturedCard()
        .padding(20)
        .background(Color(.systemGroupedBackground))
}

#Preview("Both Cards") {
    ScrollView {
        VStack(spacing: 20) {
            GrowFeaturedCard()
            PlatformFeaturedCard()
        }
        .padding(20)
    }
    .background(Color(.systemGroupedBackground))
}
