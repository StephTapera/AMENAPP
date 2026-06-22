import SwiftUI

struct AdaptiveHeaderScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct AdaptiveHeaderScrollTracker: View {
    let coordinateSpace: String

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .preference(
                    key: AdaptiveHeaderScrollOffsetKey.self,
                    value: geo.frame(in: .named(coordinateSpace)).minY
                )
        }
        .frame(height: 0)
    }
}

enum AdaptiveHeaderMetrics {
    static func progress(offset: CGFloat, collapseDistance: CGFloat) -> CGFloat {
        guard collapseDistance > 0 else { return 0 }
        return min(max((-offset) / collapseDistance, 0), 1)
    }
}

private struct AdaptiveLiquidGlassHeaderSurfaceModifier: ViewModifier {
    let progress: CGFloat
    let cornerRadius: CGFloat
    let tint: Color

    func body(content: Content) -> some View {
        let p = min(max(progress, 0), 1)

        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .background {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint.opacity(0.04 + (p * 0.05)))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.18 + (p * 0.12)),
                                        .white.opacity(0.06 + (p * 0.05)),
                                        .white.opacity(0.025)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .blendMode(.screen)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.74 + (p * 0.14)),
                                        .white.opacity(0.30 + (p * 0.16)),
                                        .black.opacity(0.04 + (p * 0.05))
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1 + (p * 0.25)
                            )
                    }
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.white.opacity(0.24 + (p * 0.18)))
                            .frame(height: 1.15)
                            .padding(.horizontal, 22)
                            .padding(.top, 5)
                            .blur(radius: 0.8)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(.white.opacity(0.08 + (p * 0.08)), lineWidth: 5)
                            .blur(radius: 8)
                            .padding(1)
                    }
                    .shadow(color: .black.opacity(0.08 + (p * 0.09)), radius: 18 + (p * 10), x: 0, y: 8 + (p * 5))
                    .shadow(color: .black.opacity(0.04 + (p * 0.05)), radius: 6 + (p * 4), x: 0, y: 2 + (p * 2))
                    .shadow(color: .white.opacity(0.28 + (p * 0.18)), radius: 8, x: 0, y: -1)
                    .compositingGroup()
            }
    }
}

extension View {
    func adaptiveLiquidGlassHeaderSurface(
        progress: CGFloat,
        cornerRadius: CGFloat = 28,
        tint: Color = .white
    ) -> some View {
        modifier(
            AdaptiveLiquidGlassHeaderSurfaceModifier(
                progress: progress,
                cornerRadius: cornerRadius,
                tint: tint
            )
        )
    }
}
