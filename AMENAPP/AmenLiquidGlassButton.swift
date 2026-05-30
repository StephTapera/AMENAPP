import SwiftUI

/// A reusable glass-backed button with icon, optional label, press feedback,
/// and full accessibility support.
///
/// Usage:
/// ```swift
/// AmenLiquidGlassButton(
///     icon: "xmark",
///     shape: .circle,
///     intensity: .light,
///     accessibilityLabel: "Close"
/// ) { dismiss() }
/// ```
struct AmenLiquidGlassButton: View {
    enum GlassButtonShape {
        case circle
        case capsule
        case roundedRect(CGFloat)
    }

    let icon: String
    var label: String? = nil
    var shape: GlassButtonShape = .circle
    var intensity: AmenGlassMaterialIntensity = .light
    var size: CGFloat = 44
    let accessibilityLabel: String
    let action: () -> Void

    @State private var isPressed = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            buttonContent
                .background(buttonBackground)
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.96 : 1)
        .opacity(isEnabled ? 1 : 0.45)
        .animation(
            reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.22, dampingFraction: 0.78),
            value: isPressed
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var buttonContent: some View {
        if let label {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: size * 0.38, weight: .medium))
                Text(label)
                    .font(AMENFont.medium(14))
            }
            .foregroundStyle(.primary)
            .frame(minHeight: 44)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        } else {
            Image(systemName: icon)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: size, height: size)
        }
    }

    @ViewBuilder
    private var buttonBackground: some View {
        switch shape {
        case .circle:
            Circle()
                .fill(glassFill)
                .overlay { Circle().fill(innerGlow) }
                .overlay { Circle().strokeBorder(borderGradient, lineWidth: borderWidth) }
                .shadow(color: .black.opacity(isPressed ? 0.04 : 0.10), radius: isPressed ? 4 : 8, y: isPressed ? 1 : 3)
        case .capsule:
            Capsule(style: .continuous)
                .fill(glassFill)
                .overlay { Capsule(style: .continuous).fill(innerGlow) }
                .overlay { Capsule(style: .continuous).strokeBorder(borderGradient, lineWidth: borderWidth) }
                .shadow(color: .black.opacity(isPressed ? 0.04 : 0.10), radius: isPressed ? 4 : 8, y: isPressed ? 1 : 3)
        case .roundedRect(let radius):
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(glassFill)
                .overlay { RoundedRectangle(cornerRadius: radius, style: .continuous).fill(innerGlow) }
                .overlay { RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(borderGradient, lineWidth: borderWidth) }
                .shadow(color: .black.opacity(isPressed ? 0.04 : 0.10), radius: isPressed ? 4 : 8, y: isPressed ? 1 : 3)
        }
    }

    private var glassFill: AnyShapeStyle {
        reduceTransparency ? intensity.solidFallback : intensity.material
    }

    private var innerGlow: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(reduceTransparency ? 0 : 0.16), Color.clear],
            startPoint: .top,
            endPoint: .center
        )
    }

    private var borderGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(contrast == .increased ? 0.65 : 0.42),
                Color.white.opacity(0.10)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderWidth: CGFloat {
        contrast == .increased ? 1.0 : 0.6
    }
}
