// AmenSpaceHeroHeaderView.swift
// AMEN ConnectSpaces — Cinematic hero header for a Space page
//
// Design constraints:
//   - Gradient hero is matte; only the title overlay uses .thinMaterial (glass rule)
//   - Parallax: caller passes scrollOffset; gradient layer is translated up at 0.4× rate
//   - Shimmer animation respects @Environment(\.accessibilityReduceMotion)
//   - No AVPlayer dependency — gradient simulates muted video atmosphere

import SwiftUI

// MARK: - Badge helpers

private func badgeIcon(for variant: AmenHostBadgeVariant) -> String {
    switch variant {
    case .individual:    return "checkmark.seal.fill"
    case .church:        return "cross.fill"
    case .organization:  return "building.2.fill"
    case .nonprofit:     return "heart.fill"
    }
}

private func badgeLabel(for variant: AmenHostBadgeVariant) -> String {
    switch variant {
    case .individual:    return "Verified"
    case .church:        return "Church"
    case .organization:  return "Org"
    case .nonprofit:     return "Nonprofit"
    }
}

// MARK: - Shimmer

private struct ShimmerModifier: ViewModifier {
    let active: Bool
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        if active {
            content
                .overlay(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: phase - 0.3),
                            .init(color: .white.opacity(0.07), location: phase),
                            .init(color: .clear, location: phase + 0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .allowsHitTesting(false)
                )
                .onAppear {
                    withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) {
                        phase = 1.6
                    }
                }
        } else {
            content
        }
    }
}

private extension View {
    func amenShimmer(active: Bool) -> some View {
        modifier(ShimmerModifier(active: active))
    }
}

// MARK: - Hero gradient

private struct HeroGradientLayer: View {
    let scrollOffset: CGFloat

    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(hex: "6E4BB5").opacity(0.85), location: 0.0),
                    .init(color: Color(hex: "245B8F").opacity(0.75), location: 0.4),
                    .init(color: Color(hex: "070607"),               location: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Secondary depth layer for atmosphere
            RadialGradient(
                colors: [
                    Color(hex: "D9A441").opacity(0.18),
                    Color.clear
                ],
                center: .init(x: 0.75, y: 0.25),
                startRadius: 0,
                endRadius: 180
            )
        }
        // Parallax: translate up at 40% of scroll depth; clamp so it never pulls below baseline
        .offset(y: min(0, scrollOffset * 0.4))
    }
}

// MARK: - Verified badge chip

private struct AmenHostBadgeChip: View {
    let variant: AmenHostBadgeVariant

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: badgeIcon(for: variant))
                .font(.systemScaled(10, weight: .bold))
            Text(badgeLabel(for: variant))
                .font(.systemScaled(11, weight: .semibold))
        }
        .foregroundStyle(Color(hex: "D9A441"))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            Capsule(style: .continuous)
                .fill(Color(hex: "D9A441").opacity(0.15))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color(hex: "D9A441").opacity(0.45), lineWidth: 0.5)
                }
        }
    }
}

// MARK: - Title overlay (glass)

private struct HeroTitleBar: View {
    let spaceName: String
    let hostDisplayName: String
    let memberCount: Int
    let isSubscribed: Bool
    let isVerified: Bool
    let hostBadge: AmenHostBadgeVariant
    let onJoin: () -> Void
    let onLeave: () -> Void

    private var formattedMemberCount: String {
        memberCount >= 1000
            ? String(format: "%.1fK", Double(memberCount) / 1000.0)
            : "\(memberCount)"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Left: name stack
            VStack(alignment: .leading, spacing: 4) {
                Text(spaceName)
                    .font(.systemScaled(20, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                HStack(spacing: 6) {
                    Text(hostDisplayName)
                        .font(.systemScaled(13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.75))

                    if isVerified {
                        AmenHostBadgeChip(variant: hostBadge)
                    }
                }

            }

            Spacer(minLength: 8)

            // CTA button
            Button {
                isSubscribed ? onLeave() : onJoin()
            } label: {
                Text(isSubscribed ? "Subscribed" : "Join")
                    .font(.systemScaled(14, weight: .bold))
                    .foregroundStyle(isSubscribed ? Color.white.opacity(0.85) : Color(hex: "070607"))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background {
                        Capsule(style: .continuous)
                            .fill(
                                isSubscribed
                                    ? AnyShapeStyle(Color.white.opacity(0.18))
                                    : AnyShapeStyle(Color(hex: "D9A441"))
                            )
                            .overlay {
                                Capsule(style: .continuous)
                                    .strokeBorder(
                                        isSubscribed
                                            ? Color.white.opacity(0.30)
                                            : Color.clear,
                                        lineWidth: 0.5
                                    )
                            }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSubscribed ? "Leave space \(spaceName)" : "Join space \(spaceName)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.thinMaterial)
    }
}

// MARK: - Public view

struct AmenSpaceHeroHeaderView: View {
    let spaceName: String
    let hostDisplayName: String
    let memberCount: Int
    let isSubscribed: Bool
    let isVerified: Bool
    let hostBadge: AmenHostBadgeVariant
    let scrollOffset: CGFloat
    let onJoin: () -> Void
    let onLeave: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Matte gradient hero (clipped so parallax overflow is hidden)
                HeroGradientLayer(scrollOffset: scrollOffset)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .amenShimmer(active: !reduceMotion)

                // Glass title bar pinned to the bottom of the hero
                HeroTitleBar(
                    spaceName: spaceName,
                    hostDisplayName: hostDisplayName,
                    memberCount: memberCount,
                    isSubscribed: isSubscribed,
                    isVerified: isVerified,
                    hostBadge: hostBadge,
                    onJoin: onJoin,
                    onLeave: onLeave
                )
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 260)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Verified Church") {
    ZStack {
        Color(red: 0.027, green: 0.024, blue: 0.031).ignoresSafeArea()
        VStack(spacing: 0) {
            AmenSpaceHeroHeaderView(
                spaceName: "Elevation Worship",
                hostDisplayName: "Elevation Church",
                memberCount: 12400,
                isSubscribed: false,
                isVerified: true,
                hostBadge: .church,
                scrollOffset: 0,
                onJoin: {},
                onLeave: {}
            )
            Spacer()
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Subscribed Individual") {
    ZStack {
        Color(red: 0.027, green: 0.024, blue: 0.031).ignoresSafeArea()
        VStack(spacing: 0) {
            AmenSpaceHeroHeaderView(
                spaceName: "Daily Prayer Circle",
                hostDisplayName: "Pastor James",
                memberCount: 342,
                isSubscribed: true,
                isVerified: true,
                hostBadge: .individual,
                scrollOffset: 0,
                onJoin: {},
                onLeave: {}
            )
            Spacer()
        }
    }
    .preferredColorScheme(.dark)
}
#endif
