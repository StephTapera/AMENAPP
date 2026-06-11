import SwiftUI

struct BereanFloatingActionTray: View {
    let payload: BereanContextPayload
    let actions: [BereanContextAction]
    var onAction: (BereanContextAction) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    @Namespace private var glassNamespace
    @State private var appeared = false

    var body: some View {
        Group {
            if reduceTransparency {
                // Solid fallback — identical layout, no blur layers.
                trayChrome
                    .background(Color(.secondarySystemBackground), in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                Color.primary.opacity(colorSchemeContrast == .increased ? 0.30 : 0.10),
                                lineWidth: 0.8
                            )
                    )
            } else {
                // custom glass shim (GlassEffectModifiers.swift) — GlassEffectContainer gives the tray one
                // shared blur surface with a specular rim. .amenGlassEffect() is the
                // LAST modifier on each chip so it renders above all other layers.
                GlassEffectContainer {
                    trayChrome
                }
                .glassEffectID("berean-tray", in: glassNamespace)
            }
        }
        .shadow(
            color: Color.black.opacity(reduceTransparency ? 0.08 : 0.18),
            radius: 18,
            y: 6
        )
        .scaleEffect(appeared ? 1 : 0.94)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .amenSpringEntry) {
                appeared = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Berean actions")
    }

    // MARK: - Inner chrome (shared between glass and solid paths)

    private var trayChrome: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(actions) { action in
                    chipButton(for: action)
                }
            }
            .padding(.horizontal, 10)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Chip buttons

    @ViewBuilder
    private func chipButton(for action: BereanContextAction) -> some View {
        Button {
            onAction(action)
        } label: {
            Label(action.title, systemImage: action.systemImage)
                .labelStyle(.titleAndIcon)
                .font(.systemScaled(12, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                // Tint layer for the primary "Ask Berean" chip and solid chip fallbacks.
                .background {
                    if reduceTransparency {
                        Capsule()
                            .fill(
                                action == .askBerean
                                    ? AmenColor.accent.opacity(0.18)
                                    : Color(.tertiarySystemBackground)
                            )
                    } else if action == .askBerean {
                        // Accent wash sits below the glass specular layer.
                        Capsule()
                            .fill(AmenColor.accent.opacity(0.16))
                    }
                }
                // .amenGlassEffect() must be LAST. Omit on solid-fallback path so chips
                // don't nest glass inside the already-solid tray.
                .modify { view in
                    if reduceTransparency {
                        view
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        Color.white.opacity(
                                            colorSchemeContrast == .increased ? 0.32 : 0.18
                                        ),
                                        lineWidth: 0.8
                                    )
                            )
                    } else if #available(iOS 26.0, *) {
                        view.amenGlassEffect(in: Capsule())
                    } else {
                        view.clipShape(Capsule())
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.title)
        .animation(.amenEaseQuick, value: action)
    }
}

// MARK: - View helper for conditional modifier chains

private extension View {
    /// Applies a modifier closure inline, keeping the modifier chain readable
    /// and avoiding AnyView wrapping in branching contexts.
    @ViewBuilder
    func modify<T: View>(@ViewBuilder transform: (Self) -> T) -> some View {
        transform(self)
    }
}
