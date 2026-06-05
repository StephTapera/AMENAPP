// AmenGenerationalPresetPickerView.swift
// AMENAPP — GenerationalOS
//
// Full-screen sheet for selecting a Generational Preset on first run.
// Liquid Glass style: .ultraThinMaterial surfaces with white border strokes.
// Uses LiquidGlassTokens and AmenTheme.Colors — no duplicated color literals.
//
// Presentation contract:
//   .sheet(isPresented: $showPresetPicker) { AmenGenerationalPresetPickerView() }
// The view calls AmenGenerationalPresetService.shared to commit the selection.

import SwiftUI

// MARK: - AmenGenerationalPresetPickerView

struct AmenGenerationalPresetPickerView: View {

    // MARK: Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: State

    @State private var selectedPreset: AmenGenerationalPreset? = nil
    @State private var cardsVisible = false

    // MARK: Body

    var body: some View {
        ZStack {
            // Background: dark-glass base consistent with SettingsView dark-panel language
            Color(red: 0.07, green: 0.07, blue: 0.08)
                .ignoresSafeArea()

            // Subtle ambient glow behind the scroll area
            RadialGradient(
                colors: [Color.accentColor.opacity(0.10), Color.clear],
                center: .top,
                startRadius: 40,
                endRadius: 340
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                headerSection

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(Array(AmenGenerationalPreset.allCases.enumerated()), id: \.element) { index, preset in
                            presetCard(preset, index: index)
                        }

                        Spacer(minLength: 32)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }

                continueButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
            }
        }
        .onAppear {
            let animation: Animation = reduceMotion
                ? .easeOut(duration: LiquidGlassTokens.motionFast)
                : .spring(response: LiquidGlassTokens.motionNormal, dampingFraction: 0.82)
            withAnimation(animation) {
                cardsVisible = true
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.badge.shield.checkmark.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .opacity(cardsVisible ? 1 : 0)
                .scaleEffect(cardsVisible ? 1 : 0.85)
                .animation(
                    reduceMotion
                        ? .easeOut(duration: LiquidGlassTokens.motionFast)
                        : .spring(response: LiquidGlassTokens.motionNormal, dampingFraction: 0.72).delay(0.04),
                    value: cardsVisible
                )
                .accessibilityHidden(true)

            Text("Your Experience Preset")
                .font(.title2.bold())
                .foregroundStyle(Color(white: 0.95))
                .opacity(cardsVisible ? 1 : 0)
                .offset(y: cardsVisible ? 0 : 12)
                .animation(
                    reduceMotion
                        ? .easeOut(duration: LiquidGlassTokens.motionFast)
                        : .spring(response: LiquidGlassTokens.motionNormal, dampingFraction: 0.82).delay(0.07),
                    value: cardsVisible
                )

            Text("Choose the safety and UX calibration that fits you best. You can change this any time in Settings.")
                .font(.subheadline)
                .foregroundStyle(Color(white: 0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .opacity(cardsVisible ? 1 : 0)
                .offset(y: cardsVisible ? 0 : 10)
                .animation(
                    reduceMotion
                        ? .easeOut(duration: LiquidGlassTokens.motionFast)
                        : .spring(response: LiquidGlassTokens.motionNormal, dampingFraction: 0.82).delay(0.10),
                    value: cardsVisible
                )
        }
        .padding(.top, 32)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your Experience Preset. Choose the safety and UX calibration that fits you best. You can change this any time in Settings.")
    }

    // MARK: - Preset Card

    @ViewBuilder
    private func presetCard(_ preset: AmenGenerationalPreset, index: Int) -> some View {
        let isSelected = selectedPreset == preset

        Button {
            let selectionAnimation: Animation = reduceMotion
                ? .easeOut(duration: LiquidGlassTokens.motionFast)
                : .spring(response: 0.26, dampingFraction: 0.72)
            withAnimation(selectionAnimation) {
                selectedPreset = preset
            }
        } label: {
            HStack(spacing: 16) {
                // Icon well
                ZStack {
                    Circle()
                        .fill(
                            isSelected
                                ? Color.accentColor.opacity(0.22)
                                : Color.white.opacity(0.08)
                        )
                        .frame(width: 52, height: 52)

                    Image(systemName: preset.symbolName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(
                            isSelected
                                ? Color.accentColor
                                : Color(white: 0.70)
                        )
                }
                .animation(
                    reduceMotion
                        ? .easeOut(duration: LiquidGlassTokens.motionFast)
                        : .spring(response: 0.26, dampingFraction: 0.72),
                    value: isSelected
                )

                // Text block
                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(
                            isSelected ? Color(white: 0.97) : Color(white: 0.85)
                        )

                    Text(preset.description)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(white: 0.50))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                // Checkmark
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(
                        isSelected
                            ? Color.accentColor
                            : Color(white: 0.28)
                    )
                    .animation(
                        reduceMotion
                            ? .easeOut(duration: LiquidGlassTokens.motionFast)
                            : .spring(response: 0.26, dampingFraction: 0.72),
                        value: isSelected
                    )
            }
            .padding(16)
            .background(cardBackground(isSelected: isSelected))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(cardBorder(isSelected: isSelected))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.0 : 0.995)
        .shadow(
            color: isSelected
                ? Color.accentColor.opacity(0.18)
                : Color.black.opacity(0.10),
            radius: isSelected ? 18 : 8,
            y: isSelected ? 6 : 3
        )
        .opacity(cardsVisible ? 1 : 0)
        .offset(y: cardsVisible ? 0 : 18)
        .animation(
            reduceMotion
                ? .easeOut(duration: LiquidGlassTokens.motionFast)
                : .spring(response: LiquidGlassTokens.motionNormal, dampingFraction: 0.82)
                    .delay(Double(index) * 0.06 + 0.12),
            value: cardsVisible
        )
        .accessibilityLabel(preset.displayName)
        .accessibilityHint(preset.description + (isSelected ? ". Currently selected." : ". Tap to select."))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Card Background

    @ViewBuilder
    private func cardBackground(isSelected: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
            if isSelected {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.accentColor.opacity(0.09))
            }
        }
    }

    // MARK: - Card Border

    private func cardBorder(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(
                isSelected
                    ? Color.accentColor.opacity(0.45)
                    : Color.white.opacity(0.15),
                lineWidth: isSelected ? 1.5 : 1
            )
    }

    // MARK: - Continue Button

    private var continueButton: some View {
        Button {
            guard let preset = selectedPreset else { return }
            Task { @MainActor in
                AmenGenerationalPresetService.shared.setPreset(preset)
                AmenGenerationalPresetService.shared.hasCompletedPresetOnboarding = true
                dismiss()
            }
        } label: {
            Text("Continue")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(
                    selectedPreset != nil
                        ? Color(white: 0.06)
                        : Color(white: 0.40)
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            selectedPreset != nil
                                ? Color.accentColor
                                : Color(white: 0.20)
                        )
                )
        }
        .disabled(selectedPreset == nil)
        .animation(
            reduceMotion
                ? .easeOut(duration: LiquidGlassTokens.motionFast)
                : .spring(response: 0.32, dampingFraction: 0.82),
            value: selectedPreset != nil
        )
        .accessibilityLabel("Continue")
        .accessibilityHint(
            selectedPreset != nil
                ? "Confirm your selection and continue."
                : "Select a preset above to enable this button."
        )
    }
}

// MARK: - Preview

#Preview {
    AmenGenerationalPresetPickerView()
}
