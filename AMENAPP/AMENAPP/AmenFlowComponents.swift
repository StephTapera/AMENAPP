import SwiftUI

struct AmenFlowGatewayView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var cardColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible(), spacing: 10)]
        }
        return [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Amen Flow")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)

                Text("Help me find what is next.")
                    .font(.headline.weight(.medium))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }
            .padding(.horizontal, 2)

            VStack(spacing: 10) {
                AmenFlowCurrentCard()

                AmenNowCapsule(
                    mode: .continueReflection,
                    title: "Continue Reflection",
                    subtitle: "Return to prayer, Scripture, or notes when you are ready.",
                    actionTitle: "Continue"
                )

                LazyVGrid(columns: cardColumns, spacing: 10) {
                    NavigationLink {
                        ChurchSearchView()
                    } label: {
                        AmenFlowRouteCard(
                            title: "Find a Church",
                            subtitle: "Help me find a real local church.",
                            icon: "building.columns.fill",
                            tint: AmenTheme.Colors.amenBlue
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens local church discovery")

                    NavigationLink {
                        SpacesDiscoveryView()
                    } label: {
                        AmenFlowRouteCard(
                            title: "Amen Spaces",
                            subtitle: "Help me join a spiritual conversation.",
                            icon: "person.3.fill",
                            tint: Color(red: 0.64, green: 0.18, blue: 0.52)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens Amen Spaces discovery")

                    NavigationLink {
                        ChurchNotesView()
                    } label: {
                        AmenFlowRouteCard(
                            title: "Church Notes",
                            subtitle: "Help me continue what God is teaching me.",
                            icon: "note.text.badge.plus",
                            tint: Color(red: 0.15, green: 0.45, blue: 0.34)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens Church Notes")

                    NavigationLink {
                        AmenUniversalSearchView()
                    } label: {
                        AmenFlowRouteCard(
                            title: "Search Amen",
                            subtitle: "Scripture, prayers, notes, spaces, churches.",
                            icon: "magnifyingglass.circle.fill",
                            tint: Color(red: 0.54, green: 0.20, blue: 0.82)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens Amen search")
                }
            }
        }
        .padding(16)
        .background(gatewayBackground, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.black.opacity(colorSchemeContrast == .increased ? 0.16 : (reduceTransparency ? 0.10 : 0.055)), lineWidth: colorSchemeContrast == .increased ? 1.1 : 0.7)
        }
        .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
    }

    private var gatewayBackground: some ShapeStyle {
        reduceTransparency ? AnyShapeStyle(Color.white) : AnyShapeStyle(.ultraThinMaterial)
    }
}

enum AmenNowCapsuleMode {
    case nowReading
    case nowPraying
    case nowListening
    case continueReflection

    var icon: String {
        switch self {
        case .nowReading: return "book.pages.fill"
        case .nowPraying: return "hands.sparkles.fill"
        case .nowListening: return "waveform.circle.fill"
        case .continueReflection: return "sparkles.rectangle.stack.fill"
        }
    }

    var accessibilityPrefix: String {
        switch self {
        case .nowReading: return "Now Reading"
        case .nowPraying: return "Now Praying"
        case .nowListening: return "Now Listening"
        case .continueReflection: return "Continue Reflection"
        }
    }
}

struct AmenNowCapsule: View {
    let mode: AmenNowCapsuleMode
    let title: String
    let subtitle: String
    let actionTitle: String
    var action: () -> Void = {}

    @State private var isExpanded = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        Button {
            if isExpanded {
                action()
            } else {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.16) : .spring(response: 0.34, dampingFraction: 0.82)) {
                    isExpanded = true
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: mode.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.black, in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.black.opacity(0.62))
                        .lineLimit(isExpanded ? 2 : 1)
                }

                Spacer(minLength: 0)

                Text(isExpanded ? actionTitle : "")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, isExpanded ? 11 : 0)
                    .padding(.vertical, isExpanded ? 7 : 0)
                    .background(Color.black, in: Capsule())
                    .opacity(isExpanded ? 1 : 0)
                    .accessibilityHidden(!isExpanded)

                Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black.opacity(0.42))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(capsuleBackground, in: Capsule())
            .overlay(Capsule().strokeBorder(colorSchemeContrast == .increased ? Color.black.opacity(0.14) : Color.white.opacity(reduceTransparency ? 0.90 : 0.64), lineWidth: colorSchemeContrast == .increased ? 1.1 : 0.8))
            .shadow(color: .black.opacity(reduceTransparency ? 0.08 : 0.10), radius: 16, y: 7)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(mode.accessibilityPrefix). \(title). \(subtitle)")
        .accessibilityHint(isExpanded ? "Activates \(actionTitle)" : "Expands the capsule")
    }

    private var capsuleBackground: some ShapeStyle {
        reduceTransparency ? AnyShapeStyle(Color.white) : AnyShapeStyle(.ultraThinMaterial)
    }
}

private struct AmenFlowCurrentCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.black, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Discover / Amen Flow")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .lineLimit(2)

                Text("A calm starting point for prayer, Scripture, church, and community discovery.")
                    .font(.subheadline)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .lineLimit(3)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(AmenTheme.Colors.surfaceCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.7)
        }
    }
}

private struct AmenFlowRouteCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(tint, in: Circle())

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
        .padding(12)
        .background(AmenTheme.Colors.surfaceCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.7)
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .scaleEffect(reduceMotion ? 1 : 0.998)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
    }
}

struct AmenFlowIntentBanner: View {
    let title: String
    let message: String
    let icon: String
    var isDarkSurface: Bool = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isDarkSurface ? Color.white : Color.black)
                .frame(width: 34, height: 34)
                .background(surfaceFill.opacity(isDarkSurface ? 0.16 : 0.08), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isDarkSurface ? Color.white : Color.black)
                    .lineLimit(2)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(isDarkSurface ? Color.white.opacity(0.68) : Color.black.opacity(0.64))
                    .lineLimit(3)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(bannerBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(isDarkSurface ? Color.white.opacity(0.10) : Color.black.opacity(0.06), lineWidth: 0.7)
        }
        .accessibilityElement(children: .combine)
    }

    private var surfaceFill: Color {
        isDarkSurface ? .white : .black
    }

    private var bannerBackground: some ShapeStyle {
        if isDarkSurface {
            return reduceTransparency ? AnyShapeStyle(Color.white.opacity(0.08)) : AnyShapeStyle(.ultraThinMaterial)
        }
        return reduceTransparency ? AnyShapeStyle(Color.white) : AnyShapeStyle(.regularMaterial)
    }
}
