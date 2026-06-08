import SwiftUI

// MARK: - CTA Button Style
// Dark pill readable over any hero image.

private struct HeroCTAButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .minimumScaleFactor(0.7)
            .lineLimit(2)
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background {
                Capsule()
                    .fill(.black.opacity(configuration.isPressed ? 0.50 : 0.65))
                    .overlay {
                        Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
                    }
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Badge Pill
// Clear-material pill floating over the hero image.

struct HeroBadgePill: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.caption.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
    }
}

// MARK: - HeroStatCell
// Shared 3-column metric cell used across all hero card types.

struct HeroStatCell: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - AmenUniversalHeroCard

/// Generic expandable hero card: large image at top with title/CTA overlay,
/// optional floating badge pills, and arbitrary expandable content below.
/// Chevron at bottom is the explicit expand/collapse trigger.
///
/// Usage:
/// ```swift
/// AmenUniversalHeroCard(
///     heroURL: url, title: "Crosspoint Church", subtitle: "Phoenix, AZ",
///     ctaLabel: "Plan Visit", badges: ["Kids", "Young Adults"], onCTA: { ... }
/// ) {
///     MyExpandedContent()
/// }
/// ```
struct AmenUniversalHeroCard<ExpandedContent: View>: View {
    let heroURL: URL?
    let title: String
    let subtitle: String
    let ctaLabel: String
    let badges: [String]
    let onCTA: () -> Void
    @ViewBuilder var expandedContent: () -> ExpandedContent

    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let heroHeight: CGFloat = 228
    private let cornerRadius: CGFloat = 28

    var body: some View {
        VStack(spacing: 0) {
            heroLayer

            if isExpanded {
                expandedLayer
            }

            chevronRow
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.11), radius: 22, x: 0, y: 10)
    }

    // MARK: Hero layer

    private var heroLayer: some View {
        ZStack(alignment: .bottom) {
            heroImage

            // Floating badge pills — upper right, max 3
            if !badges.isEmpty {
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 6) {
                            ForEach(badges.prefix(3), id: \.self) { badge in
                                HeroBadgePill(label: badge)
                            }
                        }
                    }
                    Spacer()
                }
                .padding(14)
            }

            // Bottom gradient overlay
            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .center,
                endPoint: .bottom
            )

            // Title + CTA row
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 8)
                Button(ctaLabel, action: onCTA)
                    .buttonStyle(HeroCTAButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .frame(height: heroHeight)
        // Tapping the hero image collapses the card when expanded.
        // This is the primary escape when the bottom chevron has scrolled out of the
        // visible fold inside the outer page ScrollView.
        .onTapGesture {
            guard isExpanded else { return }
            withAnimation(reduceMotion ? .none : .spring(response: 0.42, dampingFraction: 0.78)) {
                isExpanded = false
            }
        }
        .accessibilityHint(isExpanded ? "Tap to collapse" : "")
    }

    @ViewBuilder
    private var heroImage: some View {
        if let url = heroURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    placeholderGradient
                }
            }
            .frame(maxWidth: .infinity, maxHeight: heroHeight)
            .clipped()
        } else {
            placeholderGradient
                .frame(maxWidth: .infinity, maxHeight: heroHeight)
        }
    }

    private var placeholderGradient: some View {
        LinearGradient(
            colors: [Color(.systemGray4), Color(.systemGray5)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: Expanded layer
    //
    // The expanded section is height-capped and internally scrollable so that an
    // expanded card never inflates the hosting horizontal carousel row beyond
    // a predictable size, preventing the outer page ScrollView from getting "stuck".

    private let expandedMaxHeight: CGFloat = 420

    private var expandedLayer: some View {
        VStack(spacing: 0) {
            Divider().padding(.horizontal, 20)

            // Close affordance — always visible at the top of the expanded section,
            // so the user can dismiss without needing to find the chevron at the bottom.
            HStack {
                Spacer()
                Button {
                    withAnimation(reduceMotion ? .none : .spring(response: 0.42, dampingFraction: 0.78)) {
                        isExpanded = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Collapse details")
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 2)

            // Cap height and make the detail area internally scrollable so a
            // content-heavy card (e.g. Church with AI match reasons) does not push
            // the enclosing horizontal carousel row to an unbounded height.
            ScrollView(.vertical, showsIndicators: false) {
                expandedContent().padding(20)
            }
            .frame(maxHeight: expandedMaxHeight)
        }
        .transition(
            reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
        )
    }

    // MARK: Chevron

    private var chevronRow: some View {
        Button {
            withAnimation(reduceMotion ? .none : .spring(response: 0.42, dampingFraction: 0.78)) {
                isExpanded.toggle()
            }
        } label: {
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.systemScaled(13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
        }
        .accessibilityLabel(isExpanded ? "Collapse details" : "Expand details")
    }
}
