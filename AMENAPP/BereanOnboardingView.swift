//
//  BereanOnboardingView.swift
//  AMENAPP
//
//  Premium Berean AI onboarding — matches teal/seafoam reference design.
//  4-step flow: Welcome → Notifications → Microphone → Personalization
//

import SwiftUI
import AVFoundation
import UserNotifications

// MARK: - Step Enum

enum BereanOnboardingStep: Int, CaseIterable {
    case welcome = 0
    case notifications = 1
    case microphone = 2
    case personalization = 3
}

// MARK: - Onboarding Coordinator (entry point)

struct BereanOnboardingView: View {
    @Binding var isPresented: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step: BereanOnboardingStep = .welcome
    @State private var isTransitioning = false

    // Personalization selections (passed forward to step 4)
    @State private var selectedFoci: Set<String> = []
    @State private var conciseMode: Bool = true

    var body: some View {
        ZStack {
            // Full-screen gradient background — always present
            GradientBackgroundView()

            // Vertical side label — always visible
            VerticalSideLabelView()

            // Bottom-right brand glyph
            BereanBrandGlyph()

            // Step content with transitions
            ZStack {
                switch step {
                case .welcome:
                    WelcomeStepView(onContinue: advance, onLearnMore: {})
                        .transition(stepTransition)
                case .notifications:
                    NotificationsStepView(onAllow: advance, onSkip: advance)
                        .transition(stepTransition)
                case .microphone:
                    MicrophoneStepView(onEnable: advance, onSkip: advance)
                        .transition(stepTransition)
                case .personalization:
                    PersonalizationStepView(
                        selectedFoci: $selectedFoci,
                        conciseMode: $conciseMode,
                        onStart: complete
                    )
                    .transition(stepTransition)
                }
            }
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.82), value: step)

            // Glass spinner overlay during transitions
            if isTransitioning {
                GlassSpinner()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isTransitioning)
    }

    private var stepTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
    }

    private func advance() {
        guard !isTransitioning else { return }
        let nextRaw = step.rawValue + 1
        guard let next = BereanOnboardingStep(rawValue: nextRaw) else {
            complete()
            return
        }

        isTransitioning = true
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()

        // 250ms smart loading pause simulating warm-up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation {
                step = next
                isTransitioning = false
            }
        }
    }

    private func complete() {
        UserDefaults.standard.set(true, forKey: "berean_onboarding_completed")
        UserDefaults.standard.set(conciseMode, forKey: "berean_concise_mode")
        UserDefaults.standard.set(Array(selectedFoci), forKey: "berean_focus_topics")

        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)

        withAnimation(.easeInOut(duration: 0.35)) {
            isPresented = false
        }
    }
}

// MARK: - Gradient Background

struct GradientBackgroundView: View {
    // Matches the reference: light seafoam top-left → deeper teal bottom-right, radial vignette
    var body: some View {
        ZStack {
            // Base gradient
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.75, green: 0.87, blue: 0.86), location: 0.0),
                    .init(color: Color(red: 0.62, green: 0.80, blue: 0.80), location: 0.35),
                    .init(color: Color(red: 0.38, green: 0.60, blue: 0.62), location: 0.75),
                    .init(color: Color(red: 0.25, green: 0.45, blue: 0.48), location: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Radial center highlight (the soft bright orb in reference)
            RadialGradient(
                stops: [
                    .init(color: Color(red: 0.82, green: 0.92, blue: 0.90).opacity(0.6), location: 0.0),
                    .init(color: Color.clear, location: 0.65)
                ],
                center: .init(x: 0.45, y: 0.38),
                startRadius: 0,
                endRadius: 320
            )

            // Vignette (darken corners)
            RadialGradient(
                stops: [
                    .init(color: Color.clear, location: 0.5),
                    .init(color: Color(red: 0.15, green: 0.30, blue: 0.32).opacity(0.35), location: 1.0)
                ],
                center: .center,
                startRadius: 100,
                endRadius: 480
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Step Indicator (circled number)

struct StepIndicatorView: View {
    let step: BereanOnboardingStep
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var number: String {
        // Unicode circled digits 1-4
        let circled = ["①", "②", "③", "④"]
        return circled[step.rawValue]
    }

    var body: some View {
        Text(number)
            .font(.system(size: 28, weight: .light, design: .rounded))
            .foregroundStyle(.white.opacity(0.85))
            .scaleEffect(appeared ? 1.0 : (reduceMotion ? 1.0 : 0.6))
            .opacity(appeared ? 1.0 : 0.0)
            .onAppear {
                withAnimation(reduceMotion ? .easeIn(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.65).delay(0.05)) {
                    appeared = true
                }
            }
            .onChange(of: step) { _, _ in
                appeared = false
                withAnimation(reduceMotion ? .easeIn(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.65).delay(0.08)) {
                    appeared = true
                }
            }
    }
}

// MARK: - Vertical Side Label

struct VerticalSideLabelView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Orange accent dot
            Circle()
                .fill(Color(red: 0.93, green: 0.38, blue: 0.22))
                .frame(width: 6, height: 6)
                .padding(.bottom, 6)

            Text("Berean.")
                .font(.system(size: 13, weight: .medium, design: .default))
                .foregroundStyle(.white.opacity(0.75))
                .tracking(1.5)
                .rotationEffect(.degrees(90))
                .fixedSize()
                .frame(width: 13)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, 56)
        .padding(.trailing, 20)
        .allowsHitTesting(false)
    }
}

// MARK: - Brand Glyph (bottom-right)

struct BereanBrandGlyph: View {
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                ZStack {
                    Circle()
                        .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                        .frame(width: 36, height: 36)
                    Text("B.")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.trailing, 24)
                .padding(.bottom, 36)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Primary CTA Button

struct PrimaryCTAButton: View {
    let label: String
    let isLoading: Bool
    let action: () -> Void

    @State private var glowPulse: Bool = false
    @State private var isPressed: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: {
            let haptic = UIImpactFeedbackGenerator(style: .medium)
            haptic.impactOccurred()
            // Intensify glow on tap
            withAnimation(.easeOut(duration: 0.12)) { glowPulse = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeIn(duration: 0.2)) { glowPulse = false }
            }
            action()
        }) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(0.85)
                } else {
                    Text(label)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                ZStack {
                    // Glass base
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.white.opacity(0.18))
                    // Subtle top highlight
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.25), .clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                    // Border
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.white.opacity(0.35), lineWidth: 0.75)
                }
            )
            // Idle glow pulse
            .shadow(
                color: .white.opacity(glowPulse ? 0.45 : (reduceMotion ? 0 : 0.18)),
                radius: glowPulse ? 18 : 10,
                x: 0, y: 0
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        withAnimation(.easeOut(duration: 0.1)) { isPressed = true }
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { isPressed = false }
                }
        )
        .onAppear {
            guard !reduceMotion else { return }
            // Idle glow pulse loop
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true).delay(0.8)) {
                glowPulse = true
            }
        }
        .disabled(isLoading)
    }
}

// MARK: - Secondary CTA Button

struct SecondaryCTAButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.white.opacity(0.65))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Typing Text

struct TypingText: View {
    let fullText: String
    let delay: TimeInterval

    @State private var displayed: String = ""
    @State private var typingTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(displayed.isEmpty ? " " : displayed) // keep layout stable
            .multilineTextAlignment(.center)
            .onAppear { startTyping() }
            .onDisappear { typingTask?.cancel() }
    }

    private func startTyping() {
        typingTask?.cancel()
        displayed = ""
        if reduceMotion {
            displayed = fullText
            return
        }
        typingTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            for char in fullText {
                guard !Task.isCancelled else { return }
                await MainActor.run { displayed.append(char) }
                try? await Task.sleep(nanoseconds: 22_000_000) // ~22ms per char
            }
        }
    }
}

// MARK: - Glass Spinner

struct GlassSpinner: View {
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            // Dim background
            Color.black.opacity(0.12)
                .ignoresSafeArea()

            // Glass pill
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(.white.opacity(0.2), lineWidth: 0.75)

                // Arc spinner
                Circle()
                    .trim(from: 0, to: 0.72)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.9), .white.opacity(0.1)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .frame(width: 22, height: 22)
                    .rotationEffect(.degrees(rotation))
            }
            .frame(width: 60, height: 60)
            .shadow(color: .black.opacity(0.12), radius: 16, y: 4)
        }
        .onAppear {
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// MARK: - Reusable Onboarding Screen Container

struct OnboardingScreenContainer<Content: View>: View {
    let step: BereanOnboardingStep
    @ViewBuilder let content: () -> Content

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Top: step indicator (centered)
            StepIndicatorView(step: step)
                .padding(.top, 72)

            Spacer()

            content()

            Spacer()
            Spacer()
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : (reduceMotion ? 0 : 12))
        .onAppear {
            withAnimation(reduceMotion ? .easeIn(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.8).delay(0.05)) {
                appeared = true
            }
        }
    }
}

// MARK: - Step 1: Welcome

struct WelcomeStepView: View {
    let onContinue: () -> Void
    let onLearnMore: () -> Void

    @State private var titleAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        OnboardingScreenContainer(step: .welcome) {
            VStack(spacing: 32) {
                // Title
                Text("Meet Berean AI")
                    .font(.system(size: 44, weight: .light, design: .default))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .scaleEffect(titleAppeared ? 1.0 : (reduceMotion ? 1.0 : 0.88))
                    .opacity(titleAppeared ? 1.0 : 0.0)
                    .padding(.horizontal, 28)

                // Subtitle with typing effect
                TypingText(
                    fullText: "Scripture-grounded answers.\nClear sources. Calm guidance.",
                    delay: 0.55
                )
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.white.opacity(0.75))
                .lineSpacing(5)
                .padding(.horizontal, 36)

                Spacer().frame(height: 24)

                // Buttons
                VStack(spacing: 14) {
                    PrimaryCTAButton(label: "Continue", isLoading: false, action: onContinue)

                    SecondaryCTAButton(label: "Learn how it works", action: onLearnMore)
                }
                .padding(.horizontal, 28)
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeIn(duration: 0.25) : .spring(response: 0.55, dampingFraction: 0.72).delay(0.12)) {
                titleAppeared = true
            }
        }
    }
}

// MARK: - Step 2: Notifications

struct NotificationsStepView: View {
    let onAllow: () -> Void
    let onSkip: () -> Void

    @State private var isRequesting = false
    @State private var titleAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        OnboardingScreenContainer(step: .notifications) {
            VStack(spacing: 32) {
                // Icon
                Image(systemName: "bell")
                    .font(.system(size: 38, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.85))

                // Title
                Text("Gentle reminders")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .scaleEffect(titleAppeared ? 1.0 : (reduceMotion ? 1.0 : 0.88))
                    .opacity(titleAppeared ? 1.0 : 0.0)
                    .padding(.horizontal, 28)

                // Subtitle with typing effect
                TypingText(
                    fullText: "We can send follow-ups for your notes\nand prayers — only if you want.",
                    delay: 0.45
                )
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.white.opacity(0.72))
                .lineSpacing(5)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)

                Spacer().frame(height: 20)

                // Inline explainer chip
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13))
                    Text("We'll ask before sending any notification.")
                        .font(.system(size: 13, weight: .regular))
                }
                .foregroundStyle(.white.opacity(0.55))
                .padding(.horizontal, 36)

                Spacer().frame(height: 8)

                // Buttons
                VStack(spacing: 14) {
                    PrimaryCTAButton(
                        label: isRequesting ? "" : "Allow notifications",
                        isLoading: isRequesting,
                        action: {
                            guard !isRequesting else { return }
                            isRequesting = true
                            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
                                DispatchQueue.main.async {
                                    isRequesting = false
                                    onAllow()
                                }
                            }
                        }
                    )

                    SecondaryCTAButton(label: "Not now", action: onSkip)
                }
                .padding(.horizontal, 28)
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeIn(duration: 0.25) : .spring(response: 0.55, dampingFraction: 0.72).delay(0.1)) {
                titleAppeared = true
            }
        }
    }
}

// MARK: - Step 3: Microphone

struct MicrophoneStepView: View {
    let onEnable: () -> Void
    let onSkip: () -> Void

    @State private var isRequesting = false
    @State private var deniedTip = false
    @State private var micScale: CGFloat = 1.0
    @State private var titleAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        OnboardingScreenContainer(step: .microphone) {
            VStack(spacing: 32) {
                // Breathing mic glyph
                Image(systemName: "mic")
                    .font(.system(size: 42, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.85))
                    .scaleEffect(micScale)
                    .onAppear {
                        guard !reduceMotion else { return }
                        withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                            micScale = 1.04
                        }
                    }

                // Title
                Text("Ask by voice")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .scaleEffect(titleAppeared ? 1.0 : (reduceMotion ? 1.0 : 0.88))
                    .opacity(titleAppeared ? 1.0 : 0.0)
                    .padding(.horizontal, 28)

                // Subtitle (no typing — keep snappy)
                Text("Use your mic for hands-free questions.\nYou control this anytime.")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .padding(.horizontal, 36)

                // Denied tip
                if deniedTip {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13))
                        Text("Enable in Settings › Privacy › Microphone")
                            .font(.system(size: 13))
                    }
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 36)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Spacer().frame(height: 8)

                // Buttons
                VStack(spacing: 14) {
                    PrimaryCTAButton(
                        label: isRequesting ? "" : "Enable microphone",
                        isLoading: isRequesting,
                        action: {
                            guard !isRequesting else { return }
                            isRequesting = true
                            AVAudioApplication.requestRecordPermission { granted in
                                DispatchQueue.main.async {
                                    isRequesting = false
                                    if granted {
                                        onEnable()
                                    } else {
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                            deniedTip = true
                                        }
                                    }
                                }
                            }
                        }
                    )

                    SecondaryCTAButton(label: "Skip", action: onSkip)
                }
                .padding(.horizontal, 28)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: deniedTip)
        .onAppear {
            withAnimation(reduceMotion ? .easeIn(duration: 0.25) : .spring(response: 0.55, dampingFraction: 0.72).delay(0.1)) {
                titleAppeared = true
            }
        }
    }
}

// MARK: - Focus Chip

struct FocusChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    @State private var chipScale: CGFloat = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: {
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
            if !reduceMotion {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.5)) {
                    chipScale = 1.08
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                        chipScale = 1.0
                    }
                }
            }
            action()
        }) {
            Text(label)
                .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.65))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    ZStack {
                        Capsule().fill(isSelected ? .white.opacity(0.22) : .white.opacity(0.08))
                        Capsule().strokeBorder(
                            isSelected ? .white.opacity(0.6) : .white.opacity(0.2),
                            lineWidth: 0.75
                        )
                    }
                )
                .shadow(color: isSelected ? .white.opacity(0.2) : .clear, radius: 8)
        }
        .buttonStyle(.plain)
        .scaleEffect(chipScale)
    }
}

// MARK: - Step 4: Personalization

struct PersonalizationStepView: View {
    @Binding var selectedFoci: Set<String>
    @Binding var conciseMode: Bool
    let onStart: () -> Void

    private let foci = ["Bible Q&A", "Historical context", "Sermon notes", "Prayer help", "Life guidance"]

    @State private var titleAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasSelection: Bool { !selectedFoci.isEmpty }

    var body: some View {
        OnboardingScreenContainer(step: .personalization) {
            VStack(spacing: 28) {
                // Title
                Text("What should\nBerean focus on?")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .scaleEffect(titleAppeared ? 1.0 : (reduceMotion ? 1.0 : 0.88))
                    .opacity(titleAppeared ? 1.0 : 0.0)
                    .padding(.horizontal, 24)

                Text("Pick as many as you like")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white.opacity(0.55))

                // Chip grid — uses app-wide FlowLayout: Layout
                FlowLayout(spacing: 10) {
                    ForEach(foci, id: \.self) { topic in
                        FocusChip(
                            label: topic,
                            isSelected: selectedFoci.contains(topic)
                        ) {
                            if selectedFoci.contains(topic) {
                                selectedFoci.remove(topic)
                            } else {
                                selectedFoci.insert(topic)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)

                // Concise toggle
                HStack(spacing: 12) {
                    Text("Keep answers concise")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.white.opacity(0.80))

                    Spacer()

                    Toggle("", isOn: $conciseMode)
                        .labelsHidden()
                        .tint(.white.opacity(0.9))
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.white.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(.white.opacity(0.18), lineWidth: 0.75)
                        )
                )
                .padding(.horizontal, 28)

                Spacer().frame(height: 4)

                // Start button — brightens with selection
                PrimaryCTAButton(
                    label: "Start",
                    isLoading: false,
                    action: onStart
                )
                .padding(.horizontal, 28)
                .opacity(hasSelection ? 1.0 : 0.65)
                .animation(.easeInOut(duration: 0.25), value: hasSelection)
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeIn(duration: 0.25) : .spring(response: 0.55, dampingFraction: 0.72).delay(0.1)) {
                titleAppeared = true
            }
        }
    }
}


// MARK: - Preview

#Preview {
    BereanOnboardingView(isPresented: .constant(true))
}
