// AmenPrayerPrivacyPickerView.swift
// AMEN App — CommunityOS / Prayer OS (Phase 2 — Agent A7)
//
// Reusable vertical-list privacy level picker for use in the Prayer OS composer.
// Distinct from PrayerPrivacySelector (grid variant) — this view uses a
// full-width vertical card list with icon, name, and description per row,
// suitable for modal/sheet compose flows.
//
// Design contract (C3):
//   - Selected option: white card + accentColor left border accent + accentColor icon
//   - Unselected: tertiarySystemFill background, secondaryLabel icon
//   - Anonymous option shows an explanation note beneath its description
//   - 28pt continuous corner radius on all cards
//   - 44pt minimum touch target per option row
//   - Private is visually emphasised as the default with "(Recommended)" caption
//   - System colors only — no hex values
//
// Usage:
//   AmenPrayerPrivacyPickerView(selection: $selectedPrivacy)
//   AmenPrayerPrivacyPickerView(selection: $selectedPrivacy, includeAnonymous: false)

import SwiftUI

// MARK: - AmenPrayerPrivacyPickerView

/// Full-width vertical list picker for prayer privacy levels.
/// Used inside compose sheets where horizontal space is available.
struct AmenPrayerPrivacyPickerView: View {

    @Binding var selection: PrayerPrivacyLevel

    /// When false, the `.anonymous` option is hidden (e.g. for church-only contexts).
    var includeAnonymous: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var visibleLevels: [PrayerPrivacyLevel] {
        includeAnonymous
            ? PrayerPrivacyLevel.allCases
            : PrayerPrivacyLevel.allCases.filter { $0 != .anonymous }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header
            Label("Who can see this prayer?", systemImage: "lock.shield")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color(uiColor: .label))
                .accessibilityAddTraits(.isHeader)

            // Option cards
            VStack(spacing: 8) {
                ForEach(visibleLevels, id: \.self) { level in
                    privacyRow(for: level)
                }
            }
        }
    }

    // MARK: - Privacy Row

    private func privacyRow(for level: PrayerPrivacyLevel) -> some View {
        let isSelected = selection == level

        return Button {
            withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.15)) {
                selection = level
            }
        } label: {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            isSelected
                                ? Color.accentColor.opacity(0.12)
                                : Color(uiColor: .tertiarySystemFill)
                        )
                        .frame(width: 40, height: 40)

                    Image(systemName: level.systemImage)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(
                            isSelected ? Color.accentColor : Color(uiColor: .secondaryLabel)
                        )
                }
                .accessibilityHidden(true)

                // Text content
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(level.displayName)
                            .font(.callout)
                            .fontWeight(isSelected ? .semibold : .regular)
                            .foregroundStyle(Color(uiColor: .label))

                        if level == .private {
                            Text("Recommended")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(Color.accentColor.opacity(0.10))
                                )
                        }
                    }

                    Text(level.description)
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(1)

                    // Extra note for anonymous option
                    if level == .anonymous {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 10))
                            Text("Your identity is not shown to other users.")
                                .font(.caption2)
                        }
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                        .padding(.top, 2)
                    }
                }

                Spacer(minLength: 0)

                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.accentColor : Color(uiColor: .tertiaryLabel))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.white : Color(uiColor: .secondarySystemFill))
                    .shadow(
                        color: isSelected ? .black.opacity(0.06) : .clear,
                        radius: 10,
                        x: 0,
                        y: 3
                    )
            )
            .overlay(
                // Left accent bar for selected state
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.clear)
                    .frame(width: 4)
                    .frame(maxHeight: .infinity)
                    .padding(.vertical, 10),
                alignment: .leading
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(level.displayName)\(level == .private ? ", Recommended" : ""). \(level.description)\(level == .anonymous ? " Your identity is not shown to other users." : "")"
        )
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    AmenPrayerPrivacyPickerViewPreview()
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
}

private struct AmenPrayerPrivacyPickerViewPreview: View {
    @State private var selection: PrayerPrivacyLevel = .private

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            AmenPrayerPrivacyPickerView(selection: $selection)

            HStack {
                Text("Selected:")
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                Text(selection.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.accentColor)
            }

            Divider()

            Text("Without Anonymous")
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(Color(uiColor: .secondaryLabel))

            AmenPrayerPrivacyPickerView(selection: $selection, includeAnonymous: false)
        }
    }
}
#endif
