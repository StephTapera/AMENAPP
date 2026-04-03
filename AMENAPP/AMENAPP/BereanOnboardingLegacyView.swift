//
//  BereanOnboardingView.swift
//  AMENAPP
//
//  First-time onboarding for Berean AI Assistant.
//  Liquid glass design — warm white background, animated step indicator,
//  floating icon, staggered chips, and personalization grid on step 3.
//

import SwiftUI

// MARK: - Step Data

private struct OnboardingStep {
    let eyebrow: String
    let title: String
    let body: String
    let icon: String
    let chips: [String]
    let accentColors: [Color]
}

private let onboardingSteps: [OnboardingStep] = [
    OnboardingStep(
        eyebrow: "WELCOME TO BEREAN",
        title: "A calm intelligence layer for AMEN.",
        body: "Scripture-aware guidance, thoughtful reflection, and practical help for church life — all in an experience that feels quiet, clear, and trustworthy.",
        icon: "sparkles",
        chips: ["Smart, not noisy", "Built for reflection", "Fast and private"],
        accentColors: [Color(red: 0.82, green: 0.88, blue: 1.0), Color.white]
    ),
    OnboardingStep(
        eyebrow: "WHAT BEREAN HELPS WITH",
        title: "Church Notes, prayer, discovery, and scripture.",
        body: "Use Berean to understand verses, organize your Church Notes, prepare for a first visit, and get grounded suggestions without the UI feeling cluttered or robotic.",
        icon: "book.fill",
        chips: ["Church Notes", "Find a Church", "Prayer prompts"],
        accentColors: [Color(red: 1.0, green: 0.93, blue: 0.78), Color(red: 0.82, green: 0.96, blue: 0.88)]
    ),
    OnboardingStep(
        eyebrow: "TRUST BY DESIGN",
        title: "Helpful, but never a replacement for real people.",
        body: "Berean encourages Scripture, community, and wise leadership. It can guide, reflect, and prompt — but it will always point you back to real church and human support.",
        icon: "shield.checkmark.fill",
        chips: ["Human-first", "Safe by design", "Community-oriented"],
        accentColors: [Color(red: 1.0, green: 0.84, blue: 0.88), Color(red: 0.90, green: 0.84, blue: 1.0)]
    ),
    OnboardingStep(
        eyebrow: "MAKE IT YOURS",
        title: "Choose what matters most to you.",
        body: "Pick your starting focus so Berean can surface what's most helpful for you from day one.",
        icon: "slider.horizontal.3",
        chips: [],
        accentColors: [Color(red: 0.78, green: 0.95, blue: 1.0), Color(red: 0.82, green: 0.88, blue: 1.0)]
    )
]

private let personalizationOptions: [(label: String, icon: String)] = [
    ("Bible understanding", "book.fill"),
    ("Prayer support", "hands.sparkles.fill"),
    ("Find a Church", "building.columns.fill"),
    ("Voice questions", "mic.fill")
]

// MARK: - BereanOnboardingView

struct BereanOnboardingView: View {
    let onComplete: () -> Void

    @State private var currentStep: Int = 0
    @State private var iconOffset: CGFloat = 0.0
    @State private var chipOpacities: [Double] = [0, 0, 0]
    @State private var chipOffsets: [CGFloat] = [8, 8, 8]
    @State private var pulseDot: Bool = false
    @State private var selectedPersonalization: Set<String> = []
    /// Tracks whether the last step change was a forward (true) or backward (false) navigation.
    /// Used to flip the slide direction so back-navigation feels correct.
    @State private var isNavigatingForward: Bool = true
    /// Guard flag that prevents staggered chip animations from being queued multiple times
    /// when onAppear fires or a parent re-render triggers animateChips() concurrently.
    @State private var chipsAnimating: Bool = false

    var body: some View {
        ZStack {
            // Warm white background
            Color(white: 0.97)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Step indicator nav bar
                stepIndicator
                    .padding(.horizontal, 20)
                    .padding(.top, 60)

                // Main content card
                // Insertion/removal edges flip based on navigation direction so that
                // tapping Back slides the card in from the left (not the right).
                ZStack {
                    stepCardView(for: currentStep)
                        .id(currentStep)
                        .transition(.asymmetric(
                            insertion: .move(edge: isNavigatingForward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: isNavigatingForward ? .leading : .trailing).combined(with: .opacity)
                        ))
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)

                Spacer()

                // Status footer
                statusFooter
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)

                // Bottom CTA bar
                ctaBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 36)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            animateChips()
        }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack {
            // Back button — glass circle, dimmed on step 0
            Button {
                if currentStep > 0 {
                    isNavigatingForward = false
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        currentStep -= 1
                    }
                    resetAndAnimateChips()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundStyle(.black.opacity(0.7))
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial)
                    .background(Color.white.opacity(0.65))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.black.opacity(0.05), lineWidth: 0.5))
            }
            .opacity(currentStep == 0 ? 0.3 : 1)
            .animation(.easeInOut(duration: 0.2), value: currentStep)

            Spacer()

            // Progress dots — active dot expands to 24 pt
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black.opacity(i <= currentStep ? 0.7 : 0.2))
                        .frame(width: i == currentStep ? 24 : 8, height: 8)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentStep)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .background(Color.white.opacity(0.55))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.black.opacity(0.05), lineWidth: 0.5))

            Spacer()

            // Step counter
            Text("\(currentStep + 1) / 4")
                .font(.systemScaled(12))
                .foregroundStyle(.black.opacity(0.4))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .background(Color.white.opacity(0.65))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.black.opacity(0.05), lineWidth: 0.5))
        }
    }

    // MARK: - Step Card

    @ViewBuilder
    private func stepCardView(for step: Int) -> some View {
        let data = onboardingSteps[step]

        ZStack {
            // Liquid glass card layers
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Color.white.opacity(0.45))
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: data.accentColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .opacity(0.4)
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 0.5)

            VStack(alignment: .leading, spacing: 20) {
                // Icon panel
                floatingIcon(systemName: data.icon)

                // Eyebrow
                Text(data.eyebrow)
                    .font(.systemScaled(11, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.4))
                    .kerning(1.0)

                // Title
                Text(data.title)
                    .font(.systemScaled(24, weight: .bold))
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(2)

                // Body text card
                bodyCard(text: data.body)

                // Chips or personalization grid
                if step == 3 {
                    personalizationGrid
                } else {
                    chipRow(chips: data.chips)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Floating Icon

    private func floatingIcon(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.systemScaled(28, weight: .medium))
            .foregroundStyle(.black.opacity(0.72))
            .frame(width: 64, height: 64)
            .background(.ultraThinMaterial)
            .background(Color.white.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 0.5)
            )
            .offset(y: iconOffset)
            .onAppear {
                withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                    iconOffset = -4
                }
            }
    }

    // MARK: - Body Card

    private func bodyCard(text: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.6))

            Text(text)
                .font(.systemScaled(15))
                .foregroundStyle(.black.opacity(0.72))
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
                .padding(16)
        }
    }

    // MARK: - Chip Row (staggered entrance)

    private func chipRow(chips: [String]) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(chips.enumerated()), id: \.offset) { index, chip in
                Text(chip)
                    .font(.systemScaled(13, weight: .medium))
                    .foregroundStyle(.black.opacity(0.8))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial)
                    .background(Color.white.opacity(0.55))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.black.opacity(0.05), lineWidth: 0.5))
                    .opacity(index < chipOpacities.count ? chipOpacities[index] : 1)
                    .offset(y: index < chipOffsets.count ? chipOffsets[index] : 0)
            }
        }
    }

    // MARK: - Personalization Grid (step 3)

    private var personalizationGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(personalizationOptions, id: \.label) { option in
                let isSelected = selectedPersonalization.contains(option.label)
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                        if isSelected {
                            selectedPersonalization.remove(option.label)
                        } else {
                            selectedPersonalization.insert(option.label)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: option.icon)
                            .font(.systemScaled(14, weight: .medium))
                            .foregroundStyle(.black.opacity(isSelected ? 0.85 : 0.5))

                        Text(option.label)
                            .font(.systemScaled(13, weight: .medium))
                            .foregroundStyle(.black.opacity(isSelected ? 0.85 : 0.65))
                            .multilineTextAlignment(.leading)

                        Spacer()

                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.systemScaled(11, weight: .semibold))
                                .foregroundStyle(.black.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(isSelected ? 0.85 : 0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.black.opacity(isSelected ? 0.10 : 0.05), lineWidth: 0.5)
                    )
                    .shadow(
                        color: .black.opacity(isSelected ? 0.07 : 0),
                        radius: isSelected ? 8 : 0,
                        y: isSelected ? 3 : 0
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Status Footer

    private var statusFooter: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.black.opacity(pulseDot ? 1.0 : 0.45))
                .frame(width: 6, height: 6)
                .onAppear {
                    withAnimation(
                        .easeInOut(duration: 2.4).repeatForever(autoreverses: true)
                    ) {
                        pulseDot = true
                    }
                }

            Text("Gentle animations · High clarity · Built for AMEN")
                .font(.systemScaled(11))
                .foregroundStyle(.black.opacity(0.4))

            Spacer()

            Text("Berean · AMEN")
                .font(.systemScaled(11))
                .foregroundStyle(.black.opacity(0.4))
        }
    }

    // MARK: - CTA Bar

    private var ctaBar: some View {
        HStack(spacing: 10) {
            // Skip / Set up later
            Button {
                savePersonalizationIfNeeded()
                completeOnboarding()
            } label: {
                Text(currentStep == 3 ? "Set up later" : "Skip")
                    .font(.systemScaled(15, weight: .medium))
                    .foregroundStyle(.black.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(.ultraThinMaterial)
                    .background(Color.white.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 26)
                            .stroke(Color.black.opacity(0.05), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)

            // Next / Get Started
            Button {
                if currentStep == 3 {
                    savePersonalizationIfNeeded()
                    completeOnboarding()
                } else {
                    isNavigatingForward = true
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        currentStep += 1
                    }
                    resetAndAnimateChips()
                }
            } label: {
                Text(currentStep == 3 ? "Get Started" : "Next")
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 130, height: 54)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Navigation / Completion

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "bereanOnboardingComplete")
        withAnimation(.easeIn(duration: 0.45)) {
            onComplete()
        }
    }

    private func savePersonalizationIfNeeded() {
        guard !selectedPersonalization.isEmpty else { return }
        UserDefaults.standard.set(
            Array(selectedPersonalization),
            forKey: "bereanPersonalizationPreferences"
        )
    }

    // MARK: - Chip Animations

    private func resetAndAnimateChips() {
        chipsAnimating = false   // clear guard so the next animateChips() call is allowed
        chipOpacities = [0, 0, 0]
        chipOffsets = [8, 8, 8]
        animateChips()
    }

    private func animateChips() {
        // Guard: if an animation pass is already queued, do not queue another.
        // Rapid tapping through steps would otherwise stack multiple DispatchQueue.main.asyncAfter
        // closures, causing chips to flicker or re-animate unexpectedly.
        guard !chipsAnimating else { return }
        chipsAnimating = true
        let delays: [Double] = [0.12, 0.20, 0.28]
        for index in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delays[index]) {
                withAnimation(.easeOut(duration: 0.32)) {
                    if index < chipOpacities.count {
                        chipOpacities[index] = 1.0
                        chipOffsets[index] = 0
                    }
                }
            }
        }
    }
}
