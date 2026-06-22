// QuietModeOnboardingView.swift
// AMENAPP
//
// One-time onboarding screen that captures the user's Quiet Mode preference.
// Presented during the first "I'm going here Sunday" flow and never shown again.
// Preference is persisted globally and can be changed later from Get Ready or Settings.
//
// Design: minimal glass-surfaced card per option, soft palette, no clutter.
// Three options: Auto · Ask · Off.

import SwiftUI

// MARK: - Main Onboarding View

struct QuietModeOnboardingView: View {

    @StateObject private var service = QuietModePreferenceService.shared
    @State private var selected: QuietModePreference = .ask
    @State private var showDetail: QuietModePreference? = nil
    @State private var didConfirm = false

    let onConfirm: (QuietModePreference) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        headerSection
                            .padding(.top, 16)
                            .padding(.horizontal, 24)

                        optionCards
                            .padding(.top, 24)
                            .padding(.horizontal, 16)

                        permissionNote
                            .padding(.top, 20)
                            .padding(.horizontal, 24)

                        confirmButton
                            .padding(.top, 28)
                            .padding(.horizontal, 16)

                        skipButton
                            .padding(.top, 12)
                            .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarHidden(true)
        }
        .onAppear {
            selected = service.preference
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "moon.stars.fill")
                    .font(.systemScaled(15))
                    .foregroundStyle(Color(.systemIndigo).opacity(0.85))
                    .accessibilityHidden(true)
                Text("Church Focus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            Text("Quiet mode for church")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)

            Text("When you arrive at service, AMEN can help you stay focused by reducing distractions. Choose how you'd like this to work.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Option Cards

    private var optionCards: some View {
        VStack(spacing: 10) {
            ForEach(QuietModePreference.allCases) { pref in
                QuietModeOptionCard(
                    preference: pref,
                    isSelected: selected == pref,
                    showingDetail: showDetail == pref,
                    onSelect: {
                        withAnimation(.spring(duration: 0.35, bounce: 0.1)) {
                            selected = pref
                        }
                    },
                    onToggleDetail: {
                        withAnimation(.spring(duration: 0.35, bounce: 0.1)) {
                            showDetail = showDetail == pref ? nil : pref
                        }
                    }
                )
            }
        }
    }

    // MARK: - Permission Note

    private var permissionNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
                .accessibilityHidden(true)
            Text("Location access is only used to detect when you're near church. AMEN never stores or shares your location.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Confirm

    private var confirmButton: some View {
        Button {
            service.setPreference(selected)
            service.markOnboardingComplete()
            withAnimation(.spring(duration: 0.4, bounce: 0.08)) {
                didConfirm = true
            }
            onConfirm(selected)
        } label: {
            Text("Save preference")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color(.systemBackground))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var skipButton: some View {
        Button {
            service.markOnboardingComplete()
            onConfirm(.ask)
        } label: {
            Text("I'll set this up later")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Option Card

private struct QuietModeOptionCard: View {

    let preference: QuietModePreference
    let isSelected: Bool
    let showingDetail: Bool
    let onSelect: () -> Void
    let onToggleDetail: () -> Void

    private var accentColor: Color {
        switch preference {
        case .auto: return Color(.systemIndigo)
        case .ask:  return Color(.systemOrange)
        case .off:  return Color(.systemGray)
        }
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 0) {
                mainRow

                if showingDetail {
                    detailExpansion
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(16)
            .background(cardBackground)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preference.title)
        .accessibilityHint(isSelected ? "Selected. Double-tap to collapse details." : "Double-tap to select.")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Main Row

    private var mainRow: some View {
        HStack(spacing: 14) {
            // Icon well
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? accentColor.opacity(0.15) : Color(.tertiarySystemFill))
                    .frame(width: 44, height: 44)
                Image(systemName: preference.icon)
                    .font(.systemScaled(18, weight: .medium))
                    .foregroundStyle(isSelected ? accentColor : Color.secondary)
            }
            .accessibilityHidden(true)

            // Text
            VStack(alignment: .leading, spacing: 3) {
                Text(preference.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(preference.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            // Selection indicator + detail toggle
            VStack(spacing: 6) {
                // Selected checkmark
                ZStack {
                    Circle()
                        .strokeBorder(
                            isSelected ? accentColor : Color(.tertiaryLabel),
                            lineWidth: isSelected ? 0 : 1.5
                        )
                        .fill(isSelected ? accentColor : Color.clear)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.systemScaled(10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .accessibilityHidden(true)

                // Detail toggle
                Button(action: onToggleDetail) {
                    Image(systemName: "info.circle")
                        .font(.systemScaled(14))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showingDetail ? 0 : 0))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showingDetail ? "Hide details" : "Show details")
            }
        }
    }

    // MARK: - Detail Expansion

    private var detailExpansion: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .padding(.vertical, 12)
                .padding(.horizontal, 4)
            Text(preference.detailExplanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Card Background

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? accentColor.opacity(0.06) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected ? accentColor.opacity(0.35) : Color.primary.opacity(0.07),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
    }
}

// MARK: - Inline Quiet Mode Picker (for Get Ready screen "change" flow)

struct QuietModeInlinePicker: View {

    @StateObject private var service = QuietModePreferenceService.shared
    @State private var selected: QuietModePreference = .ask

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Church Focus setting")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 8) {
                ForEach(QuietModePreference.allCases) { pref in
                    Button {
                        withAnimation(.spring(duration: 0.3, bounce: 0.1)) {
                            selected = pref
                            service.setPreference(pref)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: pref.icon)
                                .font(.systemScaled(11))
                                .accessibilityHidden(true)
                            Text(pref.title)
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundStyle(selected == pref ? Color(.systemBackground) : Color.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            Capsule()
                                .fill(selected == pref ? Color.primary : Color(.tertiarySystemFill))
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(pref.title)
                    .accessibilityAddTraits(selected == pref ? [.isSelected] : [])
                }
            }
        }
        .onAppear { selected = service.preference }
    }
}

#if DEBUG
#Preview("Quiet Mode Onboarding") {
    QuietModeOnboardingView(onConfirm: { _ in })
}
#endif
