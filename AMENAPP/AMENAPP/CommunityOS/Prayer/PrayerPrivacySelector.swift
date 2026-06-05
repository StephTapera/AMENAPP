// PrayerPrivacySelector.swift
// AMEN App — Community OS / Prayer OS (A7)
//
// A visual 6-option privacy picker for prayer requests.
// PRIVATE is the default and is visually emphasized as the safe, recommended choice.
//
// Design contract (C3):
//   - LazyVGrid, 3 columns
//   - Selected: white bg + accentColor border (2pt) + accentColor icon
//   - Unselected: secondarySystemFill bg, secondaryLabel icon
//   - "Private" card shows "(Recommended)" caption2 label underneath
//   - Lock icon next to private + trustedCircle for visual trust signal
//   - 28pt continuous corner radius on cards
//   - 44x44pt minimum tap target

import SwiftUI

// MARK: - PrayerPrivacySelector

/// Visual 6-option picker for prayer request privacy.
/// Presents all PrayerPrivacyLevel cases in a 3-column grid.
/// Private is visually emphasized as the recommended default.
struct PrayerPrivacySelector: View {

    @Binding var selection: PrayerPrivacyLevel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header
            Label("Who can see this prayer?", systemImage: "lock.shield")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color(uiColor: .label))
                .accessibilityAddTraits(.isHeader)

            // Privacy card grid
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(PrayerPrivacyLevel.allCases, id: \.self) { level in
                    privacyCard(for: level)
                }
            }

            // Tooltip for selected level
            selectedDescription
        }
    }

    // MARK: - Card

    private func privacyCard(for level: PrayerPrivacyLevel) -> some View {
        let isSelected = selection == level

        return Button {
            withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.15)) {
                selection = level
            }
        } label: {
            VStack(spacing: 6) {
                // Icon row (lock indicator for high-trust levels)
                HStack(spacing: 4) {
                    if level.isHighTrustLevel && level != .private {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(isSelected ? Color.accentColor : Color(uiColor: .tertiaryLabel))
                    }
                    Image(systemName: level.systemImage)
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(isSelected ? Color.accentColor : Color(uiColor: .secondaryLabel))
                }

                // Label
                Text(level.displayName)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? Color(uiColor: .label) : Color(uiColor: .secondaryLabel))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                // "Recommended" badge — private only
                if level == .private {
                    Text("Recommended")
                        .font(.caption2)
                        .foregroundStyle(isSelected ? Color.accentColor : Color(uiColor: .tertiaryLabel))
                        .lineLimit(1)
                } else {
                    // Spacer to maintain consistent card height when no badge
                    Text(" ")
                        .font(.caption2)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.white : Color(uiColor: .secondarySystemFill))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                isSelected ? Color.accentColor : Color.clear,
                                lineWidth: 2
                            )
                    )
                    .shadow(
                        color: isSelected ? .black.opacity(0.07) : .clear,
                        radius: 8,
                        x: 0,
                        y: 2
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(level.displayName)\(level == .private ? ", Recommended" : ""). \(level.description)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Selected Description Tooltip

    @ViewBuilder
    private var selectedDescription: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                .accessibilityHidden(true)

            Text(selection.description)
                .font(.caption)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .padding(.horizontal, 4)
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.15), value: selection)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Privacy description: \(selection.description)")
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    VStack(spacing: 20) {
        PrayerPrivacySelectorPreview()
            .padding(20)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(uiColor: .systemGroupedBackground))
}

private struct PrayerPrivacySelectorPreview: View {
    @State private var selection: PrayerPrivacyLevel = .private
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PrayerPrivacySelector(selection: $selection)

            Text("Selected: \(selection.displayName)")
                .font(.caption)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .padding(.top, 4)
        }
    }
}
#endif
