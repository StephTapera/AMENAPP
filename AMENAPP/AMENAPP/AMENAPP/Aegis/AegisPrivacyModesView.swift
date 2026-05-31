// AegisPrivacyModesView.swift
// Aegis — Privacy Modes (C40–C43)
// Capabilities: familyPrivacyMode, churchSafetyMode, minorProtectionMode, highRiskRegionMode

import SwiftUI

struct AegisPrivacyModesView: View {
    @StateObject private var service = AegisPrivacyModeService.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Ordered modes C40→C43
    private let modes: [(capability: AegisCapability, icon: String, description: String)] = [
        (.familyPrivacyMode,
         "figure.2.and.child.holdinghands",
         "Protect your family's privacy, restrict child content reach, and require consent for family tags."),
        (.churchSafetyMode,
         "building.columns.fill",
         "Verified church features, restrict pastoral content to members, flag external donation requests."),
        (.minorProtectionMode,
         "shield.lefthalf.filled",
         "Restrict DMs from non-connections, age-appropriate content only, communal channels enforced."),
        (.highRiskRegionMode,
         "globe.europe.africa.fill",
         "Hides your location and network, delays location posts, protects your identity in sensitive regions.")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Active Mode Banner
                    if let activeConfig = service.modeConfigs.first(where: { $0.isActive }) {
                        activeBanner(for: activeConfig)
                    }

                    // Mode Cards
                    ForEach(modes, id: \.capability) { item in
                        modeCard(
                            capability: item.capability,
                            icon: item.icon,
                            description: item.description
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Privacy Modes")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.amenGold)
                    }
                    .accessibilityLabel("Back")
                }
            }
            .safeAreaInset(edge: .top) {
                Text("Tailor how others see you on AMEN.")
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Active Mode Banner

    @ViewBuilder
    private func activeBanner(for config: AegisPrivacyModeConfig) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.amenGold)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Active Mode")
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(.secondary)
                Text(config.title)
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(Color.amenGold)
            }

            Spacer()

            Button {
                Task {
                    await service.deactivateCurrentMode()
                }
            } label: {
                Text("Deactivate")
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(Color.amenGold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.amenGold.opacity(0.5), lineWidth: 1)
                    )
            }
            .accessibilityLabel("Deactivate \(config.title)")
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.amenGold.opacity(0.5), lineWidth: 1.2)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Mode Card

    @ViewBuilder
    private func modeCard(capability: AegisCapability, icon: String, description: String) -> some View {
        let config = service.modeConfigs.first(where: { $0.capability == capability })
        let isActive = config?.isActive ?? false
        let ruleCount = config?.rules.count ?? 0
        let flagEnabled = AegisFeatureFlags.shared.isEnabled(capability)

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isActive ? Color.amenGold.opacity(0.18) : Color(.systemFill))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isActive ? Color.amenGold : Color.secondary)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(capability.displayName)
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(isActive ? Color.amenGold : .primary)
                    if ruleCount > 0 {
                        Text("\(ruleCount) protection\(ruleCount == 1 ? "" : "s") active")
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if !flagEnabled {
                    comingSoonBadge()
                } else if isActive {
                    Button {
                        Task { await service.deactivateCurrentMode() }
                    } label: {
                        Text("Active")
                            .font(AMENFont.semiBold(13))
                            .foregroundStyle(Color.amenGold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.amenGold.opacity(0.15))
                            )
                    }
                    .accessibilityLabel("Deactivate \(capability.displayName)")
                } else {
                    Button {
                        Task { await service.activateMode(capability) }
                    } label: {
                        Text("Activate")
                            .font(AMENFont.semiBold(13))
                            .foregroundStyle(Color.amenBlue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.amenBlue.opacity(0.12))
                            )
                    }
                    .accessibilityLabel("Activate \(capability.displayName)")
                }
            }

            Text(description)
                .font(AMENFont.regular(14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(
                    isActive ? Color.amenGold.opacity(0.7) : Color.white.opacity(0.08),
                    lineWidth: isActive ? 1.5 : 0.5
                )
        )
        .opacity(flagEnabled ? 1 : 0.55)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(capability.displayName). \(description). \(ruleCount) protections. \(isActive ? "Active" : flagEnabled ? "Inactive" : "Coming soon")"
        )
    }

    // MARK: - Coming Soon Badge

    @ViewBuilder
    private func comingSoonBadge() -> some View {
        Text("Coming soon")
            .font(AMENFont.regular(11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemFill))
            )
            .accessibilityLabel("Coming soon")
    }
}

#if DEBUG
#Preview {
    AegisPrivacyModesView()
}
#endif
