import SwiftUI

struct BereanFloatingActionTray: View {
    let payload: BereanContextPayload
    let actions: [BereanContextAction]
    var onAction: (BereanContextAction) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @State private var appeared = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(actions) { action in
                    Button {
                        onAction(action)
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(chipBackground(for: action), in: Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.white.opacity(colorSchemeContrast == .increased ? 0.32 : 0.18), lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(action.title)
                }
            }
            .padding(.horizontal, 10)
        }
        .padding(.vertical, 8)
        .background(trayBackground, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(colorSchemeContrast == .increased ? 0.35 : 0.16), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(reduceTransparency ? 0.08 : 0.14), radius: 14, y: 5)
        .scaleEffect(appeared ? 1 : 0.98)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(reduceMotion ? .linear(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.86)) {
                appeared = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Berean actions")
    }

    private var trayBackground: some ShapeStyle {
        if reduceTransparency { return AnyShapeStyle(Color(.secondarySystemBackground)) }
        return AnyShapeStyle(.regularMaterial)
    }

    private func chipBackground(for action: BereanContextAction) -> some ShapeStyle {
        if action == .askBerean { return AnyShapeStyle(Color.accentColor.opacity(0.18)) }
        if reduceTransparency { return AnyShapeStyle(Color(.tertiarySystemBackground)) }
        return AnyShapeStyle(.thinMaterial)
    }
}
