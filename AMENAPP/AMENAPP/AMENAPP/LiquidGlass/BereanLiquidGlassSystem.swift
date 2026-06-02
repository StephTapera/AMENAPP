import SwiftUI
import UIKit

@MainActor
final class LiquidGlassMaterialManager: ObservableObject {
    static let shared = LiquidGlassMaterialManager()

    @Published private(set) var lowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
    @Published private(set) var reduceMotionEnabled = UIAccessibility.isReduceMotionEnabled

    private init() {
        NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.lowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        NotificationCenter.default.addObserver(
            forName: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reduceMotionEnabled = UIAccessibility.isReduceMotionEnabled
        }
    }
}

struct LiquidGlassScrollBehavior {
    var offset: CGFloat
    var velocityHint: CGFloat

    var compression: CGFloat {
        let v = min(max((abs(offset) + abs(velocityHint) * 0.2) / 220, 0), 1)
        return v
    }

    var highlightOpacity: Double {
        0.22 - (Double(compression) * 0.12)
    }

    var shadowOpacity: Double {
        0.08 + (Double(compression) * 0.10)
    }
}

struct LiquidGlassSurface<Content: View>: View {
    let cornerRadius: CGFloat
    let behavior: LiquidGlassScrollBehavior
    let content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @StateObject private var manager = LiquidGlassMaterialManager.shared

    init(cornerRadius: CGFloat, behavior: LiquidGlassScrollBehavior, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.behavior = behavior
        self.content = content()
    }

    var body: some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(surfaceFill)
                    .overlay {
                        LiquidGlassSpecularRenderer(cornerRadius: cornerRadius, opacity: behavior.highlightOpacity)
                    }
                    .overlay {
                        LiquidGlassAdaptiveBorder(cornerRadius: cornerRadius, contrastBoost: contrast == .increased)
                    }
            }
    }

    private var surfaceFill: AnyShapeStyle {
        if reduceTransparency || manager.lowPowerModeEnabled {
            return AnyShapeStyle(Color(.systemBackground).opacity(0.97))
        }
        return AnyShapeStyle(.ultraThinMaterial)
    }
}

struct LiquidGlassHighlightOverlay: View {
    let cornerRadius: CGFloat
    let offsetFactor: CGFloat
    let opacity: Double

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(opacity),
                        Color.white.opacity(0.01),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .mask(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .offset(x: offsetFactor * 14)
            )
            .allowsHitTesting(false)
    }
}

struct LiquidGlassAdaptiveBorder: View {
    let cornerRadius: CGFloat
    let contrastBoost: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                Color.black.opacity(contrastBoost ? 0.20 : 0.10),
                lineWidth: contrastBoost ? 1.0 : 0.6
            )
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.38), lineWidth: 0.4)
                    .blur(radius: 0.2)
            }
    }
}

struct LiquidGlassSpecularRenderer: View {
    let cornerRadius: CGFloat
    let opacity: Double

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(opacity),
                        Color.white.opacity(0.01),
                        Color.clear,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .blendMode(.screen)
            .allowsHitTesting(false)
    }
}

struct LiquidGlassMorphContainer<Content: View>: View {
    let id: String
    let namespace: Namespace.ID
    let cornerRadius: CGFloat
    let content: Content

    init(id: String, namespace: Namespace.ID, cornerRadius: CGFloat, @ViewBuilder content: () -> Content) {
        self.id = id
        self.namespace = namespace
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .matchedGeometryEffect(id: id, in: namespace, properties: .frame)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

enum LiquidGlassMorphAnimator {
    static var spring: Animation {
        .spring(response: 0.28, dampingFraction: 0.82)
    }
}

extension View {
    func liquidGlassPanel(_ behavior: LiquidGlassScrollBehavior, cornerRadius: CGFloat, elevated: Bool = true) -> some View {
        LiquidGlassSurface(cornerRadius: cornerRadius, behavior: behavior) {
            self
        }
        .shadow(color: .black.opacity(elevated ? 0.08 : 0.04), radius: elevated ? 12 : 6, x: 0, y: elevated ? 6 : 2)
    }
}
