// AppearanceSettingsView.swift
// AMEN — Settings/Safety system · Lane A (Appearance)
//
// Public entry surface for Appearance settings: theme mode, 10-color accent picker,
// glass intensity, and reduce-transparency. Flag-gated on ff_appearance_v2; renders a
// safe disabled state when off. Persists via AppearanceController.
//
// NOTE: named AmenAppearanceSettingsView to avoid colliding with the pre-existing
// AppearanceSettingsView in ProfileView.swift. Human to decide which becomes canonical.

import SwiftUI

struct AmenAppearanceSettingsView: View {
    var body: some View {
        SettingsFlagGate(
            .appearanceV2,
            disabledTitle: "Appearance",
            disabledReason: "Theme, accent color, and glass controls are being finalized.",
            dependency: "the appearance release flag"
        ) {
            AppearanceSettingsContent()
        }
    }
}

private struct AppearanceSettingsContent: View {
    @ObservedObject private var controller = AppearanceController.shared
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency

    private let accentColumns = [GridItem(.adaptive(minimum: 56), spacing: SettingsDesignToken.Spacing.medium)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsDesignToken.Spacing.large) {
                modeCard
                accentCard
                glassCard
            }
            .padding(SettingsDesignToken.Spacing.large)
        }
        .navigationTitle("Appearance")
        .background(AmenTheme.Colors.backgroundGrouped.ignoresSafeArea())
    }

    // MARK: - Theme mode

    private var modeCard: some View {
        SettingsSectionCard(
            title: "Theme",
            footer: "System follows your device’s light or dark setting."
        ) {
            Picker("Theme", selection: modeBinding) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(modeLabel(mode)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Theme mode")
        }
    }

    private func modeLabel(_ mode: AppearanceMode) -> String {
        switch mode {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    // MARK: - Accent

    private var accentCard: some View {
        SettingsSectionCard(
            title: "Accent Color",
            footer: "Used for highlights and interactive elements across the app."
        ) {
            LazyVGrid(columns: accentColumns, spacing: SettingsDesignToken.Spacing.medium) {
                ForEach(AccentColor.allCases) { accent in
                    accentSwatch(accent)
                }
            }
            .padding(.vertical, SettingsDesignToken.Spacing.xSmall)
        }
    }

    private func accentSwatch(_ accent: AccentColor) -> some View {
        let isSelected = controller.prefs.accent == accent
        return Button {
            var next = controller.prefs
            next.accent = accent
            controller.update(next)
        } label: {
            VStack(spacing: SettingsDesignToken.Spacing.xSmall) {
                ZStack {
                    Circle()
                        .fill(accent.color)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle().strokeBorder(AmenTheme.Colors.separatorSubtle, lineWidth: 0.5)
                        )
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(AmenTheme.Colors.textInverse)
                    }
                }
                .overlay(
                    Circle()
                        .strokeBorder(isSelected ? accent.color : Color.clear, lineWidth: 2)
                        .padding(-3)
                )
                Text(accent.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accent.displayName)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Glass

    private var glassCard: some View {
        SettingsSectionCard(
            title: "Liquid Glass",
            footer: "Reduce Transparency replaces glass surfaces with solid, high-contrast fills."
        ) {
            VStack(alignment: .leading, spacing: SettingsDesignToken.Spacing.medium) {
                VStack(alignment: .leading, spacing: SettingsDesignToken.Spacing.xSmall) {
                    HStack {
                        Text("Glass intensity")
                            .font(SettingsDesignToken.Typography.rowTitle)
                        Spacer()
                        Text("\(Int(controller.prefs.glassIntensity * 100))%")
                            .font(SettingsDesignToken.Typography.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: glassIntensityBinding, in: 0...1)
                        .disabled(effectiveReduceTransparency)
                        .accessibilityLabel("Glass intensity")
                        .accessibilityValue("\(Int(controller.prefs.glassIntensity * 100)) percent")
                }

                Divider()

                ToggleSettingRow(
                    title: "Reduce Transparency",
                    caption: systemReduceTransparency
                        ? "On at the system level. Glass is already solid everywhere."
                        : "Replace glass with solid surfaces for better contrast.",
                    binding: reduceTransparencyBinding
                )
            }
        }
    }

    private var effectiveReduceTransparency: Bool {
        systemReduceTransparency || controller.prefs.reduceTransparency
    }

    // MARK: - Bindings (route every change through the controller so it persists)

    private var modeBinding: Binding<AppearanceMode> {
        Binding(
            get: { controller.prefs.mode },
            set: { newValue in
                var next = controller.prefs
                next.mode = newValue
                controller.update(next)
            }
        )
    }

    private var glassIntensityBinding: Binding<Double> {
        Binding(
            get: { controller.prefs.glassIntensity },
            set: { newValue in
                var next = controller.prefs
                next.glassIntensity = newValue
                controller.update(next)
            }
        )
    }

    private var reduceTransparencyBinding: Binding<Bool> {
        Binding(
            get: { controller.prefs.reduceTransparency },
            set: { newValue in
                var next = controller.prefs
                next.reduceTransparency = newValue
                controller.update(next)
            }
        )
    }
}
