// AmenSimpleModeSettingsSection.swift
// AMENAPP — Accessibility
//
// A SwiftUI Section for embedding inside any settings List/Form.
// Reads and writes AmenSimpleModeService via @Environment.
//
// Placement: dropped into AccessibilitySettingsViewNew in AMENSettingsSystem.swift.
// The host view must provide the service via .environment(AmenSimpleModeService.shared).

import SwiftUI

// MARK: - AmenSimpleModeSettingsSection

struct AmenSimpleModeSettingsSection: View {

    @Environment(AmenSimpleModeService.self) private var simpleMode

    var body: some View {
        // Use @Bindable to create bindings from the @Observable object.
        @Bindable var service = simpleMode

        Section {
            // Master toggle
            Toggle(isOn: $service.isSimpleModeActive) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, alignment: .center)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Simple Mode")
                            .font(.body)
                        Text("Large buttons and text for easy navigation")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityLabel("Simple Mode")
            .accessibilityHint("Enables a simplified home screen with large buttons and text. Designed for easy one-tap actions.")

            // Font size picker — only visible when Simple Mode is on
            if simpleMode.isSimpleModeActive {
                Picker(selection: $service.fontScale) {
                    ForEach(AmenSimpleModeService.SimpleFontScale.allCases, id: \.self) { scale in
                        Text(scale.displayName).tag(scale)
                    }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "textformat.size")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, alignment: .center)
                            .padding(.top, 2)

                        Text("Text Size")
                            .font(.body)
                    }
                }
                .accessibilityLabel("Text size for Simple Mode")
                .accessibilityHint("Choose between Large or Extra Large text for the Simple Mode home screen.")

                // High contrast toggle — only visible when Simple Mode is on
                Toggle(isOn: $service.useHighContrast) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "circle.lefthalf.filled")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, alignment: .center)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("High Contrast")
                                .font(.body)
                            Text("Stronger backgrounds for better readability")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityLabel("High Contrast")
                .accessibilityHint("Uses thicker, more opaque button backgrounds and higher-contrast text in Simple Mode.")
            }

        } header: {
            Text("Simple Mode")
        } footer: {
            Text(simpleMode.isSimpleModeActive
                 ? "Simple Mode is on. The home screen shows five large action buttons instead of the full feed."
                 : "Designed for users who prefer large, clearly labelled buttons and minimal navigation.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#Preview("AmenSimpleModeSettingsSection — Off") {
    List {
        AmenSimpleModeSettingsSection()
    }
    .environment(AmenSimpleModeService.shared)
}

#Preview("AmenSimpleModeSettingsSection — On") {
    let svc = AmenSimpleModeService.shared
    svc.isSimpleModeActive = true
    return List {
        AmenSimpleModeSettingsSection()
    }
    .environment(svc)
}
