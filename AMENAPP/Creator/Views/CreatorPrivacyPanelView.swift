// CreatorPrivacyPanelView.swift
// AMENAPP — Creator Spotlight / Wave 3
//
// "What this touches" transparency panel.
// Fail-closed: EmptyView when creatorPrivacyPanelEnabled is false.
// NSPrivacyTracking is always false — displayed at bottom as a footer invariant.

import SwiftUI

struct CreatorPrivacyPanelView: View {

    let disclosure: PrivacyDisclosure?

    var body: some View {
        if !AMENFeatureFlags.shared.creatorPrivacyPanelEnabled {
            EmptyView()
        } else {
            content
        }
    }

    // MARK: - Content

    private var content: some View {
        List {
            if let disclosure {
                collectedSection(disclosure)
                neverCollectedSection(disclosure)
            } else {
                emptyState
            }

            trackingFooterRow
        }
        .listStyle(.insetGrouped)
        .navigationTitle("What this touches")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - What is collected

    @ViewBuilder
    private func collectedSection(_ disclosure: PrivacyDisclosure) -> some View {
        Section {
            if disclosure.touchedFields.isEmpty {
                Text("Nothing collected for this item.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(disclosure.touchedFields, id: \.fieldName) { field in
                    PrivacyFieldRow(field: field)
                }
            }
        } header: {
            Text("What is collected")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
    }

    // MARK: - What is never collected

    @ViewBuilder
    private func neverCollectedSection(_ disclosure: PrivacyDisclosure) -> some View {
        Section {
            if disclosure.neverTouchedList.isEmpty {
                Text("No explicit exclusions listed.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(disclosure.neverTouchedList, id: \.self) { item in
                    HStack(spacing: 10) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 15))
                            .accessibilityLabel("Never collected")
                        Text(item)
                            .font(.system(size: 14))
                            .foregroundStyle(.primary)
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text("What is never collected")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        Section {
            Text("Privacy information is not available for this item.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Tracking Footer

    private var trackingFooterRow: some View {
        Section {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("NSPrivacyTracking = false")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.clear)
        }
    }
}

// MARK: - Privacy Field Row

private struct PrivacyFieldRow: View {
    let field: PrivacyFieldDisclosure

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(field.fieldName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                ZoneBadge(zone: field.zone)
            }
            Text(field.purposeDescription)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Zone Badge

private struct ZoneBadge: View {
    let zone: PrivacyCoreZone

    var body: some View {
        Text(zone.displayLabel)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(zone.badgeColor)
            )
    }
}

// MARK: - PrivacyCoreZone extensions

private extension PrivacyCoreZone {
    var displayLabel: String {
        switch self {
        case .public:      return "Public"
        case .functional:  return "Functional"
        case .preference:  return "Preference"
        case .behavioral:  return "Behavioral"
        case .sensitive:   return "Sensitive"
        case .high:        return "High"
        case .identity:    return "Identity"
        }
    }

    var badgeColor: Color {
        switch self {
        case .public:      return Color(.systemGray)
        case .functional:  return Color(.systemBlue).opacity(0.7)
        case .preference:  return Color(.systemGreen)
        case .behavioral:  return Color(.systemOrange)
        case .sensitive:   return Color(.systemOrange)
        case .high:        return Color(.systemRed)
        case .identity:    return Color(.systemPurple)
        }
    }
}
