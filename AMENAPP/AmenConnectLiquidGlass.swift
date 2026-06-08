import SwiftUI

struct AmenConnectLiquidGlassSurface<Content: View>: View {
    enum Intensity {
        case ultraLight
        case light
        case readable

        var material: Material {
            switch self {
            case .ultraLight: return .ultraThinMaterial
            case .light: return .thinMaterial
            case .readable: return .regularMaterial
            }
        }
    }

    var cornerRadius: CGFloat = 26
    var intensity: Intensity = .light
    var tintOpacity: Double = 0.14
    var borderOpacity: Double = 0.34
    var isSelected: Bool = false
    var isPressed: Bool = false
    var scrollOpacity: Double = 0
    var saturationBoost: Double = 1.08
    var content: () -> Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var accessibilityContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        content()
            .background(surfaceBackground)
            .clipShape(shape)
            .overlay(borderLayer)
            .overlay(innerHighlight)
            .shadow(color: .black.opacity(reduceTransparency ? 0.05 : 0.08), radius: 18, x: 0, y: 8)
            .saturation(reduceTransparency ? 1 : saturationBoost)
            .scaleEffect(pressedScale)
            .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.82), value: isPressed)
            .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.32, dampingFraction: 0.86), value: isSelected)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var pressedScale: CGFloat {
        guard !reduceMotion else { return 1 }
        return isPressed ? 0.975 : 1
    }

    private var effectiveTintOpacity: Double {
        var value = tintOpacity + scrollOpacity
        if isSelected { value += 0.08 }
        if isPressed { value += 0.04 }
        if accessibilityContrast == .increased { value += 0.10 }
        return min(value, 0.38)
    }

    private var effectiveBorderOpacity: Double {
        var value = borderOpacity
        if isSelected { value += 0.18 }
        if isPressed { value += 0.12 }
        if accessibilityContrast == .increased { value += 0.24 }
        return min(value, 0.82)
    }

    @ViewBuilder
    private var surfaceBackground: some View {
        if reduceTransparency {
            shape.fill(colorScheme == .dark ? Color(.secondarySystemBackground) : Color.white)
        } else {
            shape.fill(intensity.material)
                .overlay(shape.fill(Color.white.opacity(effectiveTintOpacity)))
        }
    }

    private var borderLayer: some View {
        shape.strokeBorder(Color.white.opacity(effectiveBorderOpacity), lineWidth: accessibilityContrast == .increased ? 1.25 : 0.8)
    }

    private var innerHighlight: some View {
        shape
            .stroke(
                LinearGradient(
                    colors: [Color.white.opacity(isSelected ? 0.42 : 0.28), Color.white.opacity(0.02), Color.black.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
            .blendMode(.screen)
            .allowsHitTesting(false)
    }
}

struct AmenConnectGlassButton<Label: View>: View {
    var accessibilityLabel: String
    var isSelected: Bool = false
    var action: () -> Void
    var label: () -> Label

    @GestureState private var isPressed = false

    var body: some View {
        Button(action: action) {
            AmenConnectLiquidGlassSurface(
                cornerRadius: 18,
                intensity: isSelected ? .light : .ultraLight,
                tintOpacity: isSelected ? 0.20 : 0.12,
                borderOpacity: isSelected ? 0.48 : 0.28,
                isSelected: isSelected,
                isPressed: isPressed
            ) {
                label()
                    .frame(minWidth: 44, minHeight: 44)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, state, _ in state = true }
        )
    }
}

struct AmenConnectGlassPill: View {
    var title: String
    var iconName: String?
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        AmenConnectGlassButton(accessibilityLabel: title, isSelected: isSelected, action: action) {
            HStack(spacing: 7) {
                if let iconName {
                    Image(systemName: iconName)
                        .font(.systemScaled(13, weight: .semibold))
                }
                Text(title)
                    .font(.systemScaled(13, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.primary.opacity(isSelected ? 0.96 : 0.66))
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
        }
    }
}

struct AmenConnectSearchCapsule: View {
    var placeholder: String
    @Binding var text: String

    var body: some View {
        AmenConnectLiquidGlassSurface(cornerRadius: 22, intensity: .light, tintOpacity: 0.13, borderOpacity: 0.30) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(placeholder, text: $text)
                    .font(.systemScaled(15))
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
            }
            .padding(.horizontal, 15)
            .frame(height: 46)
        }
        .accessibilityLabel("Search Amen Connect")
    }
}

struct AmenConnectAICommandPill: View {
    var title: String = "AI Catch Up"
    var action: () -> Void

    var body: some View {
        AmenConnectGlassButton(accessibilityLabel: title, isSelected: true, action: action) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                Text(title)
                    .font(.systemScaled(14, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }
}

struct AmenConnectFloatingActionButton: View {
    var action: () -> Void

    var body: some View {
        AmenConnectGlassButton(accessibilityLabel: "Create in Amen Connect", isSelected: true, action: action) {
            Image(systemName: "plus")
                .font(.systemScaled(22, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 58, height: 58)
        }
    }
}

struct AmenConnectGlassHeader: View {
    var scrollOpacity: Double
    var onCatchUp: () -> Void
    var onProfile: () -> Void

    var body: some View {
        AmenConnectLiquidGlassSurface(cornerRadius: 30, intensity: .light, tintOpacity: 0.13, borderOpacity: 0.32, scrollOpacity: scrollOpacity) {
            HStack(spacing: 12) {
                Button(action: onProfile) {
                    ZStack(alignment: .bottomTrailing) {
                        Circle()
                            .fill(Color(.systemGray6))
                            .frame(width: 44, height: 44)
                            .overlay(Image(systemName: "person.fill").foregroundStyle(.primary.opacity(0.7)))
                        Circle()
                            .fill(Color.green)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Amen Connect profile and status")

                VStack(alignment: .leading, spacing: 2) {
                    Text("Amen Connect")
                        .font(.systemScaled(22, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("Trusted community workspace")
                        .font(.systemScaled(12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                AmenConnectAICommandPill(action: onCatchUp)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }
}

struct AmenConnectRoomSwitcher: View {
    @Binding var selectedRoom: AmenConnectRoom
    var rooms: [AmenConnectRoom]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        AmenConnectLiquidGlassSurface(cornerRadius: 27, intensity: .light, tintOpacity: 0.12, borderOpacity: 0.30) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(rooms) { room in
                        AmenConnectGlassPill(title: room.rawValue, iconName: room.iconName, isSelected: selectedRoom == room) {
                            let animation: Animation = reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.34, dampingFraction: 0.84)
                            withAnimation(animation) {
                                selectedRoom = room
                            }
                        }
                        .accessibilityAddTraits(selectedRoom == room ? .isSelected : [])
                    }
                }
                .padding(6)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Amen Connect rooms")
    }
}
