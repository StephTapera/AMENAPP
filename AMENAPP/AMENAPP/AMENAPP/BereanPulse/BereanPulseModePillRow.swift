import SwiftUI

struct BereanPulseModePillRow: View {
    @Binding var selectedMode: BereanPulseMode

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(BereanPulseMode.allCases) { mode in
                    Button {
                        selectedMode = mode
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: mode.systemImage)
                                .font(.systemScaled(12, weight: .medium))
                                .accessibilityHidden(true)
                            Text(String(localized: mode.titleKey))
                                .font(.systemScaled(13, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(selectedMode == mode ? Color.white : Color.black.opacity(0.78))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(minHeight: 44)
                        .background(
                            Capsule(style: .continuous)
                                .fill(selectedMode == mode ? Color.black : Color.white.opacity(0.72))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(
                                            selectedMode == mode ? Color.black : Color.black.opacity(0.08),
                                            lineWidth: 0.75
                                        )
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(String(localized: mode.titleKey)))
                    .accessibilityAddTraits(selectedMode == mode ? [.isButton, .isSelected] : .isButton)
                    .accessibilityHint(Text("Filters Berean Pulse cards by mode."))
                }
            }
            .padding(.horizontal, 18)
        }
    }
}
