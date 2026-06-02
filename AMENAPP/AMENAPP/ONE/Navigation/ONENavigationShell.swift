// ONENavigationShell.swift
// ONE — Three Zone Navigation (People · Moments · World)
// P0-I | Requires iOS 26 for glassEffect dock.
//
// Design rules enforced here:
//   • Feed content is always matte — no glassEffect on cells.
//   • Dock uses glassEffect (chrome surface, not content).
//   • All animations respect accessibilityReduceMotion.
//   • Dock compresses on scroll (velocity passed from child scrolls).

import SwiftUI

// MARK: - Entry Point (host app wraps this in an availability check)

@available(iOS 26.0, *)
struct ONENavigationShell: View {
    @State private var selectedZone: ONE.Zone = .moments
    @State private var scrollVelocity: CGFloat = 0      // negative = scrolling up (hide dock)
    @StateObject private var threadStore = ONEThreadStore()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            // ── Content ──────────────────────────────────────────────
            Group {
                switch selectedZone {
                case .people:  ONEThreadListView(store: threadStore)
                case .moments: ONELiquidCameraView()
                case .world:   ONEWorldFeedView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(edges: .bottom)

            // ── Glass Dock ────────────────────────────────────────────
            ONEGlassDock(
                selectedZone: $selectedZone,
                scrollVelocity: scrollVelocity,
                reduceMotion: reduceMotion
            )
            .padding(.bottom, 8)
            .padding(.horizontal, 16)
        }
        .background(AmenTheme.Colors.backgroundPrimary.ignoresSafeArea())
    }
}

// MARK: - Glass Dock

@available(iOS 26.0, *)
struct ONEGlassDock: View {
    @Binding var selectedZone: ONE.Zone
    let scrollVelocity: CGFloat
    let reduceMotion: Bool

    @Namespace private var dockNamespace

    private var isCompressed: Bool { scrollVelocity < -80 }

    private var selectionAnimation: Animation {
        ONE.Motion.adaptive(reduceMotion: reduceMotion)
    }

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(ONE.Zone.allCases) { zone in
                    dockButton(for: zone)
                }
            }
            .padding(.horizontal, ONE.Spacing.sm)
            .padding(.vertical, isCompressed ? 6 : 10)
        }
        .scaleEffect(y: isCompressed ? 0.92 : 1.0, anchor: .bottom)
        .opacity(isCompressed ? 0.88 : 1.0)
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.15)
                : .spring(response: 0.34, dampingFraction: 0.86),
            value: isCompressed
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Zone navigation")
    }

    @ViewBuilder
    private func dockButton(for zone: ONE.Zone) -> some View {
        let isSelected = selectedZone == zone

        Button {
            guard selectedZone != zone else { return }
            withAnimation(selectionAnimation) { selectedZone = zone }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: zone.icon)
                    .font(.system(size: isSelected ? 22 : 20, weight: isSelected ? .semibold : .regular))
                    .frame(width: 44, height: 32)
                    .animation(selectionAnimation, value: isSelected)

                Text(zone.label)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? AmenTheme.Colors.amenGold : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .glassEffect(
            isSelected
                ? .regular.tint(ONE.Colors.glassWarm).interactive()
                : .regular.interactive(),
            in: RoundedRectangle(cornerRadius: ONE.Radius.pill)
        )
        .glassEffectID(zone.id, in: dockNamespace)
        .accessibilityLabel(zone.label)
        .accessibilityHint(zone.accessibilityHint)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Zone Placeholders (replaced by real views in P1–P3)

@available(iOS 26.0, *)
struct ONEPeopleZonePlaceholder: View {
    var body: some View {
        VStack(spacing: ONE.Spacing.md) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 48))
                .foregroundStyle(AmenTheme.Colors.amenGold.opacity(0.5))
            Text("People")
                .font(.title2.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Text("Private messages, groups, and close connections.\nP1 implementation pending.")
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AmenTheme.Colors.backgroundPrimary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("People zone — coming in Phase 1")
    }
}

@available(iOS 26.0, *)
struct ONEMomentsZonePlaceholder: View {
    var body: some View {
        VStack(spacing: ONE.Spacing.md) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundStyle(AmenTheme.Colors.amenGold.opacity(0.5))
            Text("Moments")
                .font(.title2.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Text("Capture and share with your privacy contract.\nP2 implementation pending.")
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AmenTheme.Colors.backgroundPrimary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Moments zone — coming in Phase 2")
    }
}

@available(iOS 26.0, *)
struct ONEWorldZonePlaceholder: View {
    var body: some View {
        VStack(spacing: ONE.Spacing.md) {
            Image(systemName: "globe")
                .font(.system(size: 48))
                .foregroundStyle(AmenTheme.Colors.amenGold.opacity(0.5))
            Text("World")
                .font(.title2.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Text("Discover communities and public content.\nP3 implementation pending.")
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AmenTheme.Colors.backgroundPrimary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("World zone — coming in Phase 3")
    }
}

// MARK: - Preview

#if DEBUG
@available(iOS 26.0, *)
#Preview("ONE Shell") {
    ONENavigationShell()
}
#endif
