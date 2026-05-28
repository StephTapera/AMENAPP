import SwiftUI

enum DockPlacement {
    case bottom
    case top
}

private struct AmenLiquidGlassCapsuleSurface: ViewModifier {
    let isPressed: Bool
    let isSelected: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background {
                if reduceTransparency {
                    Capsule(style: .continuous)
                        .fill(Color(.systemBackground))
                } else {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(isSelected ? 0.20 : 0.12))
                        }
                }
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(
                        Color.white.opacity(isSelected ? 0.42 : 0.28),
                        lineWidth: 0.5
                    )
                    .blur(radius: 0.2)
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        Color.black.opacity(contrast == .increased ? 0.20 : (isSelected ? 0.14 : 0.10)),
                        lineWidth: contrast == .increased ? 1.0 : 0.8
                    )
            }
            .shadow(color: .black.opacity(isSelected ? 0.10 : 0.08), radius: 18, x: 0, y: 8)
            // Pattern 7: 0.96 scale with canonical bouncy spring
            .scaleEffect(reduceMotion ? 1 : (isPressed ? 0.96 : 1))
            .brightness(isPressed ? 0.02 : 0)
    }
}

private extension View {
    func amenLiquidGlassCapsuleSurface(isPressed: Bool = false, isSelected: Bool = false) -> some View {
        modifier(AmenLiquidGlassCapsuleSurface(isPressed: isPressed, isSelected: isSelected))
    }
}

struct AmenLiquidGlassPillButton: View {
    let title: String
    let systemImage: String
    let isLoading: Bool
    let isDisabled: Bool
    var hint: String? = nil
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if #available(iOS 17, *) {
                    // Pattern 8: SF Symbol scale-up on active state
                    Image(systemName: isLoading ? "hourglass" : systemImage)
                        .symbolEffect(.bounce, options: .speed(1.4), value: isPressed)
                } else {
                    Image(systemName: isLoading ? "hourglass" : systemImage)
                }
                Text(title).lineLimit(1)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .amenLiquidGlassCapsuleSurface(isPressed: isPressed, isSelected: !isDisabled && !isLoading)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isLoading)
        .opacity((isDisabled || isLoading) ? 0.6 : 1)
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, state, _ in
                    state = true
                }
        )
        // Pattern 7: canonical bouncy spring for press-state shrink
        .animation(reduceMotion ? .easeOut(duration: 0.12) : Motion.liquidSpring, value: isPressed)
        .accessibilityLabel(title)
        .accessibilityHint(hint ?? "")
    }
}

struct AmenLiquidGlassControlDock<Content: View>: View {
    let placement: DockPlacement
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8, content: content)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .amenLiquidGlassCapsuleSurface()
        .padding(.horizontal)
        .padding(placement == .bottom ? .bottom : .top, 10)
    }
}

struct AmenLiquidGlassBottomSheet<Content: View, Footer: View>: View {
    let title: String
    let subtitle: String?
    let aiDisclosure: String?
    let content: () -> Content
    let footer: () -> Footer

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline).foregroundStyle(.black)
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.black.opacity(0.8))
                }
                if let aiDisclosure {
                    AmenAIUsageLabel(text: aiDisclosure)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(sheetChromeBackground)

            ScrollView { content().padding() }
                .background(reduceTransparency ? Color(.systemBackground) : Color.white.opacity(0.92))

            footer()
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(sheetChromeBackground)
        }
    }

    @ViewBuilder
    private var sheetChromeBackground: some View {
        if reduceTransparency {
            Color(.systemBackground)
        } else {
            Rectangle()
                .fill(.regularMaterial)
                .overlay {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                }
        }
    }
}
