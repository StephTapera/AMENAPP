// AmenGenerationalPresetSettingsRow.swift
// AMENAPP — GenerationalOS
//
// A drop-in settings row for SettingsView (SDGroup / SDNavRow pattern).
// Displays the current preset label with a chevron and opens
// AmenGenerationalPresetPickerView as a sheet when tapped.

import SwiftUI

// MARK: - AmenGenerationalPresetSettingsRow

/// Settings row showing the current Generational Preset.
/// Drop this into any SDGroup block in SettingsView.
///
///     SDGroup {
///         AmenGenerationalPresetSettingsRow()
///     }
struct AmenGenerationalPresetSettingsRow: View {

    // MARK: State

    @State private var showPicker = false

    // Observe the service so the row label updates when the preset changes.
    private var service: AmenGenerationalPresetService { AmenGenerationalPresetService.shared }

    // MARK: Design tokens (matches SettingsView SD namespace)

    private enum SD {
        static let bg         = Color(red: 0.07, green: 0.07, blue: 0.08)
        static let panel      = Color(red: 0.12, green: 0.12, blue: 0.13)
        static let label      = Color(white: 0.95)
        static let secondary  = Color(white: 0.5)
        static let chevron    = Color(white: 0.32)
        static let iconBg     = Color(red: 0.36, green: 0.22, blue: 0.68) // deep-purple safety accent
    }

    // MARK: Body

    var body: some View {
        Button {
            showPicker = true
        } label: {
            HStack(spacing: 13) {
                // Icon well — matches SDNavRow icon-with-background style
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(SD.iconBg)
                    .frame(width: 30, height: 30)
                    .overlay(
                        Image(systemName: "person.badge.shield.checkmark.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                    )
                    .accessibilityHidden(true)

                // Label + subtitle
                VStack(alignment: .leading, spacing: 1) {
                    Text("Your Experience Preset")
                        .font(.systemScaled(15, weight: .regular))
                        .foregroundStyle(SD.label)
                    Text("Tap to change your safety and UX calibration")
                        .font(.systemScaled(12))
                        .foregroundStyle(SD.label.opacity(0.45))
                }

                Spacer()

                // Current preset badge + chevron
                HStack(spacing: 4) {
                    Text(service.activePreset.displayName)
                        .font(.systemScaled(13, weight: .medium))
                        .foregroundStyle(SD.secondary)

                    Image(systemName: "chevron.right")
                        .font(.systemScaled(11, weight: .medium))
                        .foregroundStyle(SD.chevron)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(SDPressStyle())
        .sheet(isPresented: $showPicker) {
            AmenGenerationalPresetPickerView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .accessibilityLabel("Your Experience Preset, currently set to \(service.activePreset.displayName)")
        .accessibilityHint("Tap to open the preset picker and change your safety and UX calibration.")
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color(red: 0.07, green: 0.07, blue: 0.08).ignoresSafeArea()
        VStack(spacing: 0) {
            AmenGenerationalPresetSettingsRow()
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.13))
        )
        .padding(.horizontal, 16)
    }
}
