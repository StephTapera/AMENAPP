// AmenAudienceSimulatorView.swift
// AMENAPP — CommunityOS/Privacy
//
// Phase 4 — Agent TS-a (Privacy Engine)
// "Who can see this?" audience simulation display.
//
// Design contract (C3 / AmenDesignSystem):
//   • Light gray expandable section (Color.systemGroupedBackground tint)
//   • White rows per viewer type with checkmark / X icons
//   • Expandable via DisclosureGroup
//   • Driven by AmenPrivacyEngine.simulateAudience(for:viewerType:)
//
// Accessibility:
//   • Each row announces viewer type + can/cannot status
//   • Section header has isHeader trait

import SwiftUI

// MARK: - AmenAudienceSimulatorView

/// Expandable "Who can see this?" panel embedded under a privacy picker.
///
/// Shows a row per `AudienceType` describing what each viewer can see/do
/// given the current `AmenPrivacyPreset`.
///
/// Usage:
/// ```swift
/// AmenAudienceSimulatorView(preset: selectedPreset)
/// ```
struct AmenAudienceSimulatorView: View {

    let preset: AmenPrivacyPreset
    @StateObject private var engine = AmenPrivacyEngine()
    @State private var isExpanded: Bool = false

    // Viewer types to display, in order
    private let viewerTypes: [AudienceType] = [
        .anonymous,
        .authenticatedStranger,
        .mutualFollow,
        .churchMember,
        .trustedContact
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Expandable header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                headerRow
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Who can see this? Tap to \(isExpanded ? "collapse" : "expand") details.")
            .accessibilityAddTraits(.isButton)

            // Expanded rows
            if isExpanded {
                Divider()
                    .padding(.horizontal, 16)

                VStack(spacing: 0) {
                    ForEach(viewerTypes, id: \.self) { viewerType in
                        let simulation = engine.simulateAudience(for: preset, viewerType: viewerType)
                        AudienceRow(simulation: simulation)

                        if viewerType != viewerTypes.last {
                            Divider()
                                .padding(.leading, 52)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .background(sectionBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "eye.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            Text("Who can see this?")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color(uiColor: .label))

            Spacer()

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Background

    private var sectionBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
    }
}

// MARK: - AudienceRow

/// Single row showing what one `AudienceType` viewer can see/do.
private struct AudienceRow: View {

    let simulation: AudienceSimulation

    var body: some View {
        HStack(spacing: 12) {
            // Viewer type icon
            Image(systemName: simulation.viewerType.systemImage)
                .font(.system(size: 16))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            // Viewer label
            Text(simulation.viewerType.displayName)
                .font(.subheadline)
                .foregroundStyle(Color(uiColor: .label))
                .frame(maxWidth: .infinity, alignment: .leading)

            // Capability columns: Posts · Profile · DMs
            HStack(spacing: 8) {
                capabilityChip(
                    label: "Posts",
                    allowed: simulation.canSeePost
                )
                capabilityChip(
                    label: "Profile",
                    allowed: simulation.canSeeProfile
                )
                capabilityChip(
                    label: "DMs",
                    allowed: simulation.canSendDM
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel)
    }

    // MARK: - Capability Chip

    private func capabilityChip(label: String, allowed: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: allowed ? "checkmark" : "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(allowed ? Color.accentColor : Color(uiColor: .tertiaryLabel))
            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(allowed ? Color(uiColor: .label) : Color(uiColor: .tertiaryLabel))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(allowed
                    ? Color.accentColor.opacity(0.08)
                    : Color(uiColor: .tertiarySystemFill))
        )
    }

    // MARK: - Accessibility

    private var rowAccessibilityLabel: String {
        let posts   = simulation.canSeePost    ? "Can see posts"    : "Cannot see posts"
        let profile = simulation.canSeeProfile ? "Can see profile"  : "Cannot see profile"
        let dms     = simulation.canSendDM     ? "Can send a DM"    : "Cannot send a DM"
        return "\(simulation.viewerType.displayName): \(posts), \(profile), \(dms)."
    }
}

// MARK: - Legend Row (used in expanded header, optional)

/// Small legend shown at the bottom of the expanded section.
private struct SimulatorLegend: View {
    var body: some View {
        HStack(spacing: 16) {
            legendItem(icon: "checkmark", label: "Allowed", tint: Color.accentColor)
            legendItem(icon: "xmark", label: "Blocked", tint: Color(uiColor: .tertiaryLabel))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Legend: checkmark means allowed, X means blocked.")
    }

    private func legendItem(icon: String, label: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Audience Simulator") {
    AudienceSimulatorPreviewWrapper()
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
}

private struct AudienceSimulatorPreviewWrapper: View {
    @State private var selected: AmenPrivacyPreset = .balanced

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Preset picker
                AmenPrivacyPresetView(selectedPreset: $selected, showDetails: false)

                // Simulator, updates with selection
                AmenAudienceSimulatorView(preset: selected)
            }
        }
    }
}
#endif
