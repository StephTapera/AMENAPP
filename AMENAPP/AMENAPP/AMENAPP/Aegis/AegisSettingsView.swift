// AegisSettingsView.swift
// Aegis — Main Hub / Entry Point
// Shown from app Settings. NavigationStack root.

import SwiftUI

struct AegisSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let policyUrl = URL(string: "https://amenapp.com/privacy")!

    var body: some View {
        NavigationStack {
            List {
                headerSection
                modesSection
                wellbeingSection
                dataSection
                safetySection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Aegis")
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
                    .accessibilityLabel("Close Aegis settings")
                }
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        Section {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [Color.amenGold.opacity(0.22), Color.amenPurple.opacity(0.14)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 60)
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Color.amenGold)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Aegis Trust & Safety")
                        .font(AMENFont.semiBold(17))
                        .foregroundStyle(.primary)
                    Text("Your protection layer — always on.")
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Aegis Trust & Safety. Your protection layer — always on.")
        }
        .listRowBackground(Color.clear)
    }

    // MARK: - Privacy Modes Section

    private var modesSection: some View {
        Section("Privacy Modes") {
            NavigationLink {
                AegisPrivacyModesView()
            } label: {
                settingsRow(
                    icon: "person.badge.shield.checkmark.fill",
                    title: "Privacy Modes",
                    subtitle: "Family, Church, Minor, High-Risk",
                    color: .amenGold
                )
            }
        }
    }

    // MARK: - Wellbeing Section

    private var wellbeingSection: some View {
        Section("Wellbeing") {
            NavigationLink {
                AegisWellbeingView()
            } label: {
                settingsRow(
                    icon: "heart.fill",
                    title: "Wellbeing",
                    subtitle: "Metrics, filters, scroll reminders, memories",
                    color: Color.amenPurple
                )
            }
        }
    }

    // MARK: - Data Section

    private var dataSection: some View {
        Section("Your Data") {
            NavigationLink {
                AegisDataRightsView()
            } label: {
                settingsRow(
                    icon: "externaldrive.fill",
                    title: "Data Rights",
                    subtitle: "Export, delete, legacy, tracking",
                    color: Color.amenBlue
                )
            }
        }
    }

    // MARK: - Safety Reports Section

    private var safetySection: some View {
        Section("Safety Reports") {
            NavigationLink {
                GuardianDashboardView()
            } label: {
                settingsRow(
                    icon: "exclamationmark.shield.fill",
                    title: "Safety Reports",
                    subtitle: "Your reports and Guardian review queue",
                    color: Color.red.opacity(0.85)
                )
            }
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section("About Aegis") {
            VStack(alignment: .leading, spacing: 10) {
                Text("What Aegis Does")
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(.primary)

                Text("Aegis is AMEN's protection layer. It monitors content for safety risks, protects vulnerable users, enforces your privacy preferences, and gives you control over your data — all without compromising the openness of your faith community.")
                    .font(AMENFont.regular(13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)

            HStack {
                Text("Policy Version")
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(AegisContractsVersion)
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Policy version \(AegisContractsVersion)")

            Button {
                openURL(policyUrl)
            } label: {
                HStack {
                    Text("Privacy Policy")
                        .font(AMENFont.regular(14))
                        .foregroundStyle(Color.amenBlue)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.amenBlue)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel("Open privacy policy in browser")
        }
    }

    // MARK: - Row Helper

    @ViewBuilder
    private func settingsRow(icon: String, title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(color.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle).")
    }
}

#if DEBUG
#Preview {
    AegisSettingsView()
}
#endif
