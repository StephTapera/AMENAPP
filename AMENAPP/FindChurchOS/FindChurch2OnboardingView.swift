// FindChurch2OnboardingView.swift
// AMENAPP — Find Church 2.0 — Liquid Glass Onboarding
//
// Phase 0: What are you looking for?  (SeekerIntent grid)
// Phase 1: What fits you?             (FitChip grid, filtered by intent)
// Phase 2: Your comfort matters       (ComfortChip grid, functional chips highlighted)
//
// Design rules enforced:
//   • .ultraThinMaterial only — no nested materials
//   • @Environment(\.accessibilityReduceMotion) guards all animations
//   • Dynamic Type text styles throughout — no fixed sizes
//   • All tap targets ≥ 44×44 pt
//   • No UITextField / TextField anywhere in this file
//   • Feature-gated: returns EmptyView when findChurch2OnboardingEnabled == false

import SwiftUI

// MARK: - FindChurch2OnboardingView

struct FindChurch2OnboardingView: View {

    // MARK: Interface
    var onComplete: (SeekerProfile.SeekerIntent?, [SeekerProfile.FitChip], [SeekerProfile.ComfortChip]) -> Void
    var onSkip: () -> Void

    // MARK: Phase state
    @State private var phase: Int = 0
    @State private var selectedIntents: Set<SeekerProfile.SeekerIntent> = []
    @State private var selectedFitChips: Set<SeekerProfile.FitChip> = []
    @State private var selectedComfortChips: Set<SeekerProfile.ComfortChip> = []

    // MARK: Environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Feature gate
    @ObservedObject private var flags = AMENFeatureFlags.shared

    // MARK: Body
    public var body: some View {
        if !flags.findChurch2OnboardingEnabled {
            EmptyView()
        } else {
            onboardingContent
        }
    }

    // MARK: - Onboarding content

    @ViewBuilder
    private var onboardingContent: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Phase pages via TabView (swipe disabled — navigation is button-driven)
                TabView(selection: $phase) {
                    Phase0View(
                        selectedIntents: $selectedIntents,
                        reduceMotion: reduceMotion
                    )
                    .tag(0)

                    Phase1View(
                        selectedIntents: selectedIntents,
                        selectedFitChips: $selectedFitChips,
                        reduceMotion: reduceMotion
                    )
                    .tag(1)

                    Phase2View(
                        selectedComfortChips: $selectedComfortChips,
                        reduceMotion: reduceMotion
                    )
                    .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(
                    reduceMotion ? .none : .spring(response: 0.32, dampingFraction: 0.85),
                    value: phase
                )

                // Bottom navigation bar (progress dots + back/next)
                BottomNavBar(
                    phase: phase,
                    reduceMotion: reduceMotion,
                    onBack: {
                        guard phase > 0 else { return }
                        withAnimation(reduceMotion ? .none : .spring(response: 0.32, dampingFraction: 0.85)) {
                            phase -= 1
                        }
                    },
                    onNext: {
                        if phase < 2 {
                            withAnimation(reduceMotion ? .none : .spring(response: 0.32, dampingFraction: 0.85)) {
                                phase += 1
                            }
                        } else {
                            onComplete(
                                selectedIntents.first,
                                Array(selectedFitChips),
                                Array(selectedComfortChips)
                            )
                        }
                    }
                )
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Skip") {
                        onSkip()
                    }
                    .font(.subheadline.weight(.medium))
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Skip onboarding")
                }
            }
        }
    }
}

// MARK: - Phase 0: What are you looking for?

private struct Phase0View: View {
    @Binding var selectedIntents: Set<SeekerProfile.SeekerIntent>
    let reduceMotion: Bool

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("What are you looking for?")
                    .font(.title)
                    .fontWeight(.bold)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 16)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(SeekerProfile.SeekerIntent.allCases, id: \.self) { intent in
                        let isSelected = selectedIntents.contains(intent)
                        IntentPill(
                            label: intent.displayName,
                            isSelected: isSelected,
                            reduceMotion: reduceMotion
                        ) {
                            withAnimation(reduceMotion ? .none : .spring(response: 0.32, dampingFraction: 0.85)) {
                                if isSelected {
                                    selectedIntents.remove(intent)
                                } else {
                                    selectedIntents.insert(intent)
                                }
                            }
                        }
                        .accessibilityLabel(intent.displayName)
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    }
                }

                // Bottom padding so content clears the bottom nav bar
                Spacer(minLength: 120)
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Phase 1: What fits you?

private struct Phase1View: View {
    let selectedIntents: Set<SeekerProfile.SeekerIntent>
    @Binding var selectedFitChips: Set<SeekerProfile.FitChip>
    let reduceMotion: Bool

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var visibleChips: [SeekerProfile.FitChip] {
        SeekerProfile.FitChip.allCases.filter { chip in
            selectedIntents.isEmpty ||
            chip.relevantIntents.contains(where: { selectedIntents.contains($0) })
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("What fits you?")
                    .font(.title)
                    .fontWeight(.bold)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 16)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(visibleChips, id: \.self) { chip in
                        let isSelected = selectedFitChips.contains(chip)
                        ChipButton(
                            label: chip.displayName,
                            sfSymbol: nil,
                            isSelected: isSelected,
                            isFunctional: false,
                            reduceMotion: reduceMotion
                        ) {
                            withAnimation(reduceMotion ? .none : .spring(response: 0.32, dampingFraction: 0.85)) {
                                if isSelected {
                                    selectedFitChips.remove(chip)
                                } else {
                                    selectedFitChips.insert(chip)
                                }
                            }
                        }
                        .accessibilityLabel(chip.displayName)
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    }
                }

                Spacer(minLength: 120)
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Phase 2: Your comfort matters

private struct Phase2View: View {
    @Binding var selectedComfortChips: Set<SeekerProfile.ComfortChip>
    let reduceMotion: Bool

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Your comfort matters")
                    .font(.title)
                    .fontWeight(.bold)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 16)

                Text("These settings stay private on your device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(SeekerProfile.ComfortChip.allCases, id: \.self) { chip in
                        let isSelected = selectedComfortChips.contains(chip)
                        ChipButton(
                            label: chip.displayName,
                            sfSymbol: chip.isFunctional ? "lock.fill" : nil,
                            isSelected: isSelected,
                            isFunctional: chip.isFunctional,
                            reduceMotion: reduceMotion
                        ) {
                            withAnimation(reduceMotion ? .none : .spring(response: 0.32, dampingFraction: 0.85)) {
                                if isSelected {
                                    selectedComfortChips.remove(chip)
                                } else {
                                    selectedComfortChips.insert(chip)
                                }
                            }
                        }
                        .accessibilityLabel(chip.displayName)
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    }
                }

                Spacer(minLength: 120)
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - IntentPill

/// Two-column intent selection pill. Full width within its grid cell.
private struct IntentPill: View {
    let label: String
    let isSelected: Bool
    let reduceMotion: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.purple.opacity(0.15))
                            }
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    isSelected ? Color.purple.opacity(0.6) : Color.clear,
                                    lineWidth: 1.5
                                )
                        }
                }
                .foregroundStyle(isSelected ? Color.purple : Color.primary)
                .animation(reduceMotion ? .none : .spring(response: 0.32, dampingFraction: 0.85), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ChipButton

/// General-purpose selection chip for FitChips and ComfortChips.
/// Functional chips (privacy) receive a lock SF symbol prefix and a distinct selected color.
private struct ChipButton: View {
    let label: String
    let sfSymbol: String?
    let isSelected: Bool
    let isFunctional: Bool
    let reduceMotion: Bool
    let action: () -> Void

    private var selectedTint: Color {
        isFunctional ? Color(red: 0.85, green: 0.70, blue: 0.20) : Color.purple  // gold for functional
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol = sfSymbol {
                    Image(systemName: symbol)
                        .font(.caption)
                        .accessibilityHidden(true)
                }
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(selectedTint.opacity(0.15))
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                isSelected ? selectedTint.opacity(0.65) : Color.clear,
                                lineWidth: 1.5
                            )
                    }
            }
            .foregroundStyle(isSelected ? selectedTint : Color.primary)
            .animation(reduceMotion ? .none : .spring(response: 0.32, dampingFraction: 0.85), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - BottomNavBar

/// Three-dot progress indicator + back/next buttons anchored to the bottom of the screen.
private struct BottomNavBar: View {
    let phase: Int
    let reduceMotion: Bool
    let onBack: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Subtle separator
            Divider()
                .background(Color.primary.opacity(0.08))

            HStack(alignment: .center) {
                // Back button (hidden on phase 0 — preserves layout space)
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .font(.body.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .opacity(phase > 0 ? 1 : 0)
                .disabled(phase == 0)
                .accessibilityLabel("Back")
                .accessibilityHidden(phase == 0)

                Spacer()

                // Three-dot progress indicator
                HStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .frame(width: 8, height: 8)
                            .foregroundStyle(index == phase ? Color.purple : Color.secondary.opacity(0.35))
                            .animation(
                                reduceMotion ? .none : .spring(response: 0.32, dampingFraction: 0.85),
                                value: phase
                            )
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Step \(phase + 1) of 3")

                Spacer()

                // Next / Find Churches button
                Button(action: onNext) {
                    HStack(spacing: 4) {
                        Text(phase == 2 ? "Find Churches" : "Next")
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "arrow.right")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(phase == 2 ? "Find Churches" : "Next")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Phase 0 — Enabled") {
    FindChurch2OnboardingView(
        onComplete: { intent, fits, comforts in
            print("Complete: intent=\(String(describing: intent)), fits=\(fits.count), comforts=\(comforts.count)")
        },
        onSkip: {
            print("Skipped")
        }
    )
}
#endif
