// ChurchCapabilitySection.swift
// AMEN Community OS — Church OS (A8)
//
// Horizontal chip row showing available church action capabilities.
// Chips use SF Symbols + labels in a horizontal ScrollView.
// Feature-gated by communityOSChurchOSEnabled (default false).
//
// Design rules (C3): system colors only, Color.accentColor for interactive,
// white cards, no amenGold/amenPurple/hex colors.

import SwiftUI

// MARK: - ChurchCapability

/// The canonical set of church action capabilities.
/// Matches the capabilities defined in the C1 Object Model for the Church type.
enum ChurchCapability: String, CaseIterable, Identifiable {
    case discuss   = "discuss"
    case pray      = "pray"
    case study     = "study"
    case events    = "events"
    case volunteer = "volunteer"
    case give      = "give"
    case notes     = "notes"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .discuss:   return "Discuss"
        case .pray:      return "Pray"
        case .study:     return "Study"
        case .events:    return "Events"
        case .volunteer: return "Volunteer"
        case .give:      return "Give"
        case .notes:     return "Notes"
        }
    }

    var systemImage: String {
        switch self {
        case .discuss:   return "bubble.left.and.bubble.right"
        case .pray:      return "hands.and.sparkles"
        case .study:     return "book.pages"
        case .events:    return "calendar"
        case .volunteer: return "heart.circle"
        case .give:      return "dollarsign.circle"
        case .notes:     return "note.text"
        }
    }
}

// MARK: - ChurchCapabilitySection

/// Horizontal chip row showing available church actions.
/// Only chips whose raw value is in `availableCapabilities` are shown.
/// When `availableCapabilities` is empty, all capabilities are shown as a default set.
struct ChurchCapabilitySection: View {

    let churchId: String
    let availableCapabilities: [String]

    /// Called when a chip is tapped. Receives the capability raw value string.
    var onCapabilityTapped: ((String) -> Void)?

    // MARK: - Feature flag

    @AppStorage("community_os_church_os_enabled")
    private var featureEnabled: Bool = false

    // MARK: - Computed capabilities

    private var resolvedCapabilities: [ChurchCapability] {
        let filtered = availableCapabilities.compactMap { ChurchCapability(rawValue: $0) }
        return filtered.isEmpty ? ChurchCapability.allCases : filtered
    }

    // MARK: - Body

    var body: some View {
        if featureEnabled {
            chipRow
                .accessibilityLabel("Church actions")
                .accessibilityHint("Scroll to see more actions")
        }
    }

    // MARK: - Chip Row

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(resolvedCapabilities) { capability in
                    ChurchCapabilityChip(
                        capability: capability,
                        onTap: { onCapabilityTapped?(capability.rawValue) }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - ChurchCapabilityChip

private struct ChurchCapabilityChip: View {

    let capability: ChurchCapability
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            Label(capability.displayName, systemImage: capability.systemImage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.accentColor.opacity(0.10))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(capability.displayName)
        .accessibilityHint("Tap to \(capability.displayName.lowercased())")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Preview

#Preview("Church SystemCapability Section") {
    VStack(alignment: .leading, spacing: 16) {
        Text("All Capabilities")
            .font(.headline)
            .padding(.horizontal)

        ChurchCapabilitySection(
            churchId: "church_preview",
            availableCapabilities: [],
            onCapabilityTapped: { cap in print("Tapped: \(cap)") }
        )

        Divider()

        Text("Subset: Discuss + Pray + Events")
            .font(.headline)
            .padding(.horizontal)

        ChurchCapabilitySection(
            churchId: "church_preview",
            availableCapabilities: ["discuss", "pray", "events"],
            onCapabilityTapped: { cap in print("Tapped: \(cap)") }
        )
    }
    .padding(.vertical)
    .background(Color(uiColor: .systemGroupedBackground))
    .onAppear {
        UserDefaults.standard.set(true, forKey: "community_os_church_os_enabled")
    }
}
