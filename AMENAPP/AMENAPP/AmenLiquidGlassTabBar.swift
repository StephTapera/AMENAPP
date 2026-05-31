import SwiftUI

enum AmenLiquidGlassTabBarScrollDirection: Equatable {
    case idle
    case up
    case down
}

enum AmenLiquidGlassTabBarScrollVelocityLevel: Equatable {
    case idle
    case slow
    case fast
}

struct AmenLiquidGlassTabBar: View {
    @Binding var selectedTab: String
    let tabs: [String]
    let isColorfulContentBehind: Bool
    let scrollDirection: AmenLiquidGlassTabBarScrollDirection
    let scrollVelocityLevel: AmenLiquidGlassTabBarScrollVelocityLevel
    let reduceMotion: Bool
    let reduceTransparency: Bool

    @Namespace private var activeTabNamespace
    @ScaledMetric(relativeTo: .caption) private var iconSize: CGFloat = 20
    @ScaledMetric(relativeTo: .caption2) private var labelSize: CGFloat = 11

    private var isCompressed: Bool {
        scrollDirection == .down || scrollVelocityLevel == .fast
    }

    private var isFastScrolling: Bool {
        scrollVelocityLevel == .fast
    }

    private var selectedTabAnimation: Animation? {
        guard !reduceMotion else { return .easeInOut(duration: 0.16) }
        guard !isFastScrolling else { return .easeOut(duration: 0.12) }
        // Pattern 2: canonical bouncy spring for pill position change
        if #available(iOS 17, *) {
            return .spring(.bouncy(duration: 0.4, extraBounce: 0.1))
        }
        return .spring(response: 0.42, dampingFraction: 0.72)
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs, id: \.self) { tab in
                tabButton(for: tab)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, isCompressed ? 6 : 8)
        .frame(maxWidth: 430)
        .background { barBackground }
        .clipShape(Capsule())
        .shadow(color: .black.opacity(reduceTransparency ? 0.14 : 0.10), radius: isCompressed ? 10 : 16, x: 0, y: isCompressed ? 5 : 9)
        .padding(.horizontal, 18)
        .scaleEffect(y: isCompressed ? 0.94 : 1.0, anchor: .bottom)
        .opacity(isCompressed ? 0.92 : 1.0)
        // Pattern 2: canonical bouncy spring for tab bar compress/expand
        .animation(reduceMotion ? .easeInOut(duration: 0.16) : Motion.liquidSpring, value: isCompressed)
        .animation(.easeOut(duration: isFastScrolling ? 0.08 : 0.18), value: isColorfulContentBehind)
        .accessibilityElement(children: .contain)
    }

    private var barBackground: some View {
        Capsule()
            .fill(reduceTransparency ? AnyShapeStyle(Color.white) : AnyShapeStyle(.ultraThinMaterial))
            .overlay {
                Capsule()
                    .fill(
                        Color.white.opacity(
                            reduceTransparency ? 1.0 : (isColorfulContentBehind ? 0.60 : 0.82)
                        )
                    )
            }
            .overlay {
                if !reduceTransparency && isColorfulContentBehind && !isFastScrolling {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.blue.opacity(0.08),
                                    Color.pink.opacity(0.055),
                                    Color.yellow.opacity(0.045)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .saturation(1.25)
                }
            }
            .overlay {
                Capsule()
                    .strokeBorder(Color.black.opacity(reduceTransparency ? 0.10 : 0.055), lineWidth: 0.6)
            }
            .overlay {
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(reduceTransparency ? 0.95 : 0.78),
                                .white.opacity(reduceTransparency ? 0.58 : 0.28),
                                .white.opacity(0.14)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.0
                    )
            }
            .overlay(alignment: .top) {
                Capsule()
                    .fill(.white.opacity(reduceTransparency ? 0.55 : 0.42))
                    .frame(height: 1)
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
            }
    }

    @ViewBuilder
    private func tabButton(for tab: String) -> some View {
        let isSelected = selectedTab == tab

        Button {
            guard selectedTab != tab else { return }
            withAnimation(selectedTabAnimation) {
                selectedTab = tab
            }
            HapticManager.impact(style: .light)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: iconName(for: tab, isSelected: isSelected))
                    .font(.system(size: iconSize, weight: .bold))
                    .symbolRenderingMode(.monochrome)
                    .frame(height: 22)

                Text(tab)
                    .font(.system(size: labelSize, weight: .semibold, design: .default))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(isSelected ? AmenTheme.Colors.amenBlue : Color.black.opacity(0.88))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .padding(.horizontal, 4)
            .background {
                if isSelected {
                    Capsule()
                        .fill(activeTabFill)
                        .overlay(Capsule().strokeBorder(.white.opacity(reduceTransparency ? 0.80 : 0.50), lineWidth: 0.8))
                        .matchedGeometryEffect(id: "amen_liquid_glass_active_tab", in: activeTabNamespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(AmenLiquidGlassTabPressStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(tab)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var activeTabFill: Color {
        if reduceTransparency {
            return Color(uiColor: .secondarySystemBackground)
        }
        if isColorfulContentBehind {
            return Color.white.opacity(isFastScrolling ? 0.56 : 0.48)
        }
        return Color.black.opacity(0.055)
    }

    private func iconName(for tab: String, isSelected: Bool) -> String {
        switch tab {
        case "#OPENTABLE":
            return isSelected ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right"
        case "Testimonies":
            return isSelected ? "star.fill" : "star"
        case "Prayer":
            return isSelected ? "hands.sparkles.fill" : "hands.sparkles"
        default:
            return isSelected ? "circle.fill" : "circle"
        }
    }
}

private struct AmenLiquidGlassTabPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // Pattern 7: unified 0.96 press-shrink with canonical bouncy spring
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1.0)
            .animation(reduceMotion ? nil : Motion.liquidSpring, value: configuration.isPressed)
    }
}

#Preview("White Background") {
    PreviewAmenLiquidGlassTabBarHost(
        selected: "#OPENTABLE",
        isColorful: false,
        direction: .idle,
        velocity: .idle,
        reduceMotion: false,
        reduceTransparency: false
    )
}

#Preview("Colorful Content Behind") {
    PreviewAmenLiquidGlassTabBarHost(
        selected: "Testimonies",
        isColorful: true,
        direction: .idle,
        velocity: .slow,
        reduceMotion: false,
        reduceTransparency: false
    )
}

#Preview("Reduce Transparency") {
    PreviewAmenLiquidGlassTabBarHost(
        selected: "Prayer",
        isColorful: true,
        direction: .idle,
        velocity: .idle,
        reduceMotion: false,
        reduceTransparency: true
    )
}

#Preview("Reduce Motion") {
    PreviewAmenLiquidGlassTabBarHost(
        selected: "#OPENTABLE",
        isColorful: true,
        direction: .up,
        velocity: .slow,
        reduceMotion: true,
        reduceTransparency: false
    )
}

#Preview("Fast Scroll") {
    PreviewAmenLiquidGlassTabBarHost(
        selected: "Prayer",
        isColorful: true,
        direction: .down,
        velocity: .fast,
        reduceMotion: false,
        reduceTransparency: false
    )
}

private struct PreviewAmenLiquidGlassTabBarHost: View {
    @State var selected: String
    let isColorful: Bool
    let direction: AmenLiquidGlassTabBarScrollDirection
    let velocity: AmenLiquidGlassTabBarScrollVelocityLevel
    let reduceMotion: Bool
    let reduceTransparency: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            if isColorful {
                LinearGradient(
                    colors: [.orange, .pink, .blue, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            } else {
                Color(.systemBackground).ignoresSafeArea()
            }

            AmenLiquidGlassTabBar(
                selectedTab: $selected,
                tabs: ["#OPENTABLE", "Testimonies", "Prayer"],
                isColorfulContentBehind: isColorful,
                scrollDirection: direction,
                scrollVelocityLevel: velocity,
                reduceMotion: reduceMotion,
                reduceTransparency: reduceTransparency
            )
            .padding(.bottom, 18)
        }
    }
}
