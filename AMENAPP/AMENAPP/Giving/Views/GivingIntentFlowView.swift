// GivingIntentFlowView.swift
// AMENAPP
//
// First-time values intake — 3 steps, lightweight and premium.
// Glass pills, spring transitions, skip allowed.
// Editable later from GivingPreferencesSheet.

import SwiftUI

struct GivingIntentFlowView: View {
    @StateObject private var vm = GivingIntentProfileViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onComplete: (GivingProfile) -> Void
    let onSkip: () -> Void

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack(alignment: .top) {
                    // Background
                    Color(uiColor: .systemGroupedBackground)
                        .ignoresSafeArea()

                    // Hero banner
                    heroBanner(safeTop: geo.safeAreaInsets.top)
                        .frame(height: 220 + geo.safeAreaInsets.top)

                    // Sheet content
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: 180 + geo.safeAreaInsets.top)
                            sheetContent
                                .padding(.bottom, 40)
                        }
                    }
                    .ignoresSafeArea(edges: .top)
                }
            }
            .ignoresSafeArea(edges: .top)
            .navigationBarHidden(true)
        }
    }

    // MARK: - Hero Banner

    private func heroBanner(safeTop: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    Color(red: 0.44, green: 0.36, blue: 0.12),
                    Color(red: 0.61, green: 0.51, blue: 0.22),
                    Color(red: 0.72, green: 0.60, blue: 0.28),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Specular highlight
            GeometryReader { g in
                RadialGradient(
                    colors: [.white.opacity(0.18), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: g.size.width * 0.7
                )
            }

            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: safeTop + 16)

                HStack {
                    Spacer()
                    Button(action: onSkip) {
                        Text("Skip")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.80))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.15), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)

                Spacer()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Giving &")
                        .font(.custom("Georgia", size: 38))
                        .foregroundStyle(.white)
                    Text("Nonprofits")
                        .font(.custom("Georgia", size: 38))
                        .foregroundStyle(.white)
                    Text("Tell us what moves you.")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.80))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Sheet Content

    private var sheetContent: some View {
        VStack(spacing: 20) {
            // Step content
            VStack(alignment: .leading, spacing: 0) {
                // Step indicator
                stepIndicator
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 20)

                Divider()

                // Animated step body
                Group {
                    switch vm.step {
                    case .causes: causesStep
                    case .geography: geographyStep
                    case .alignment: alignmentStep
                    }
                }
                .transition(
                    reduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .trailing)),
                            removal: .opacity.combined(with: .move(edge: .leading))
                          )
                )
                .animation(reduceMotion ? .none : .spring(duration: 0.32, bounce: 0.08), value: vm.step)
                .padding(20)

                Divider()

                // Navigation
                navigationButtons
                    .padding(20)
            }
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 30,
                    bottomLeadingRadius: 20,
                    bottomTrailingRadius: 20,
                    topTrailingRadius: 30,
                    style: .continuous
                )
                .fill(.regularMaterial)
                .overlay(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 30,
                        bottomLeadingRadius: 20,
                        bottomTrailingRadius: 20,
                        topTrailingRadius: 30,
                        style: .continuous
                    )
                    .strokeBorder(.white.opacity(0.30), lineWidth: 0.8)
                )
            )
            .padding(.horizontal, 16)

            // Privacy note
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("These preferences stay on your device and shape rankings — never shared for ads.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(GivingIntentProfileViewModel.IntentStep.allCases, id: \.rawValue) { step in
                Capsule()
                    .fill(vm.step == step ? AmenTheme.Colors.textPrimary : AmenTheme.Colors.backgroundSecondary)
                    .frame(width: vm.step == step ? 24 : 8, height: 6)
                    .animation(.spring(duration: 0.28), value: vm.step)
            }
            Spacer()
            Text("Step \(vm.step.rawValue + 1) of \(GivingIntentProfileViewModel.IntentStep.allCases.count)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Steps

    private var causesStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader(vm.step.title, subtitle: vm.step.subtitle)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(GivingCause.allCases) { cause in
                    causePill(cause)
                }
            }
        }
    }

    private func causePill(_ cause: GivingCause) -> some View {
        let selected = vm.selectedCauses.contains(cause)
        return Button {
            withAnimation(.spring(duration: 0.22, bounce: 0.12)) {
                vm.toggleCause(cause)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: cause.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected ? AmenTheme.Colors.textInverse : AmenTheme.Colors.textTertiary)
                Text(cause.rawValue)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected ? AmenTheme.Colors.textInverse : AmenTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? AmenTheme.Colors.textPrimary : AmenTheme.Colors.backgroundSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? .clear : AmenTheme.Colors.borderSoft, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var geographyStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader(vm.step.title, subtitle: vm.step.subtitle)

            VStack(spacing: 8) {
                ForEach(GeographicPreference.allCases, id: \.self) { pref in
                    geographyOption(pref)
                }
            }
        }
    }

    private func geographyOption(_ pref: GeographicPreference) -> some View {
        let selected = vm.geographicPreference == pref
        let icon: String
        let subtitle: String
        switch pref {
        case .localFirst:
            icon = "mappin.circle.fill"
            subtitle = "Prioritize county, metro, and city-serving organizations"
        case .balanced:
            icon = "globe.americas"
            subtitle = "Mix of local and global opportunities"
        case .global:
            icon = "globe"
            subtitle = "Organizations serving across countries and regions"
        }

        return Button {
            withAnimation(.spring(duration: 0.22)) {
                vm.geographicPreference = pref
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(selected ? AmenTheme.Colors.textInverse : AmenTheme.Colors.textTertiary)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text(pref.rawValue)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selected ? AmenTheme.Colors.textInverse : AmenTheme.Colors.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(selected ? AmenTheme.Colors.textInverse.opacity(0.75) : AmenTheme.Colors.textTertiary)
                        .lineSpacing(1)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(AmenTheme.Colors.textInverse.opacity(0.80))
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selected ? AmenTheme.Colors.textPrimary : AmenTheme.Colors.backgroundSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? .clear : AmenTheme.Colors.borderSoft, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var alignmentStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader(vm.step.title, subtitle: vm.step.subtitle)

            VStack(alignment: .leading, spacing: 12) {
                Text("Theological alignment")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1.2)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(TheologicalAlignment.allCases, id: \.self) { alignment in
                            GlassSelectablePill(
                                label: alignment.rawValue,
                                isSelected: vm.theologicalAlignment == alignment,
                                onTap: { vm.theologicalAlignment = alignment }
                            )
                        }
                    }
                }

                Text("Giving style")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .padding(.top, 4)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(GivingStyle.allCases, id: \.self) { style in
                            GlassSelectablePill(
                                label: style.rawValue,
                                isSelected: vm.givingStyles.contains(style),
                                onTap: { vm.toggleStyle(style) }
                            )
                        }
                    }
                }
            }
        }
    }

    private func stepHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .lineSpacing(2)
        }
    }

    // MARK: - Navigation

    private var navigationButtons: some View {
        HStack(spacing: 12) {
            if !vm.step.isFirst {
                Button(action: vm.retreat) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .frame(width: 44, height: 44)
                        .background(AmenTheme.Colors.backgroundSecondary, in: Circle())
                }
                .buttonStyle(.plain)
            }

            Button {
                if vm.step.isLast {
                    let profile = vm.buildProfile()
                    onComplete(profile)
                } else {
                    vm.advance()
                }
            } label: {
                Text(vm.step.isLast ? "Show my feed →" : "Continue")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.textInverse)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(AmenTheme.Colors.buttonPrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
            }
            .buttonStyle(.plain)
        }
    }
}
