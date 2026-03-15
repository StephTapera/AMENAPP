//
//  BereanOnboardingView.swift
//  AMENAPP
//
//  Berean AI onboarding — redesigned to match the new light atmospheric aesthetic.
//  Background: near-white (#F2F2F7) with soft red/coral and purple blobs at
//  bottom corners, matching the main Berean chat redesign.
//
//  All logic preserved:
//   - 4-step flow: Welcome → Notifications → Microphone → Personalization
//   - Permission requests (UNUserNotificationCenter, AVAudioApplication)
//   - UserDefaults persistence (berean_onboarding_completed, concise_mode, focus_topics)
//   - FlowLayout chip grid, TypingText, GlassSpinner
//   - Haptic feedback
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

    @State private var selectedFoci: Set<String> = []
    @State private var conciseMode: Bool = true

    // Atmospheric orb animations
    @State private var orbLeft = false
    @State private var orbRight = false
    @State private var orbCenter = false

    var body: some View {
        ZStack {
            // MARK: Light atmospheric background
            Color(red: 0.949, green: 0.949, blue: 0.969)
                .ignoresSafeArea()

            // Bottom-corner atmospheric blobs
            ZStack {
                // Bottom-left — warm red/coral
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 1.0, green: 0.35, blue: 0.35).opacity(0.28),
                                Color(red: 1.0, green: 0.45, blue: 0.30).opacity(0.13),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 240
                        )
                    )
                    .frame(width: 480, height: 480)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .offset(x: -100, y: 100)
                    .blur(radius: 75)
                    .scaleEffect(orbLeft ? 1.07 : 1.0)
                    .animation(.easeInOut(duration: 8).repeatForever(autoreverses: true), value: orbLeft)
                    .allowsHitTesting(false)

                // Bottom-right — violet/purple
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.58, green: 0.25, blue: 0.95).opacity(0.22),
                                Color(red: 0.45, green: 0.20, blue: 0.80).opacity(0.10),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 220
                        )
                    )
                    .frame(width: 440, height: 440)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .offset(x: 100, y: 80)
                    .blur(radius: 65)
                    .scaleEffect(orbRight ? 1.10 : 1.0)
                    .animation(.easeInOut(duration: 7).repeatForever(autoreverses: true), value: orbRight)
                    .allowsHitTesting(false)

                // Center warmth
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 1.0, green: 0.75, blue: 0.40).opacity(0.10),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 180
                        )
                    )
                    .frame(width: 360, height: 360)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .offset(y: 60)
                    .blur(radius: 55)
                    .scaleEffect(orbCenter ? 1.15 : 1.0)
                    .animation(.easeInOut(duration: 5.5).repeatForever(autoreverses: true), value: orbCenter)
                    .allowsHitTesting(false)
            }

            // Berean brand mark — top trailing
            BereanLightBrandMark()

            // Step indicator dots — bottom center
            LightStepDots(current: step.rawValue, total: BereanOnboardingStep.allCases.count)

            // Step content
            ZStack {
                switch step {
                case .welcome:
                    LightWelcomeStepView(onContinue: advance, onLearnMore: {})
                        .transition(stepTransition)
                case .notifications:
                    LightNotificationsStepView(onAllow: advance, onSkip: advance)
                        .transition(stepTransition)
                case .microphone:
                    LightMicrophoneStepView(onEnable: advance, onSkip: advance)
                        .transition(stepTransition)
                case .personalization:
                    LightPersonalizationStepView(
                        selectedFoci: $selectedFoci,
                        conciseMode: $conciseMode,
                        onStart: complete
                    )
                    .transition(stepTransition)
                }
            }
            .animation(
                reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.82),
                value: step
            )

            // Glass spinner during transitions
            if isTransitioning {
                GlassSpinner()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isTransitioning)
        .onAppear {
            withAnimation { orbLeft = true; orbRight = true; orbCenter = true }
        }
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
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

// MARK: - Brand Mark (top trailing)

private struct BereanLightBrandMark: View {
    var body: some View {
        VStack {
            HStack {
                Spacer()
                HStack(spacing: 5) {
                    ZStack {
                        Circle()
                            .fill(Color(white: 0.94))
                            .frame(width: 26, height: 26)
                            .overlay(Circle().stroke(Color(white: 0.88), lineWidth: 0.5))
                        Text("B")
                            .font(.system(size: 13, weight: .light, design: .serif))
                            .foregroundStyle(Color(white: 0.35))
                    }
                    Text("Berean.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(white: 0.45))
                        .tracking(0.5)
                }
                .padding(.trailing, 22)
                .padding(.top, 58)
            }
            Spacer()
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Step Dots (bottom center)

private struct LightStepDots: View {
    let current: Int
    let total: Int

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<total, id: \.self) { index in
                    Capsule()
                        .fill(
                            index == current
                                ? Color(red: 1.0, green: 0.42, blue: 0.28)
                                : Color(white: 0.75)
                        )
                        .frame(width: index == current ? 20 : 6, height: 6)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: current)
                }
            }
            .padding(.bottom, 44)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Reusable Light Onboarding Screen Container

private struct LightOnboardingContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 80)
            content()
            Spacer(minLength: 80)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : (reduceMotion ? 0 : 16))
        .onAppear {
            withAnimation(reduceMotion ? .easeIn(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.8).delay(0.04)) {
                appeared = true
            }
        }
    }
}

// MARK: - Light Primary CTA Button

struct LightPrimaryCTAButton: View {
    let label: String
    let isLoading: Bool
    let action: () -> Void

    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: {
            let haptic = UIImpactFeedbackGenerator(style: .medium)
            haptic.impactOccurred()
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
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.48, blue: 0.30),
                                    Color(red: 0.95, green: 0.32, blue: 0.18)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.18), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
            )
            .shadow(
                color: Color(red: 1.0, green: 0.35, blue: 0.18).opacity(0.35),
                radius: 12,
                y: 4
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
        .disabled(isLoading)
    }
}

// MARK: - Light Secondary CTA Button

private struct LightSecondaryCTAButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color(white: 0.50))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - TypingText (preserved)

struct TypingText: View {
    let fullText: String
    let delay: TimeInterval

    @State private var displayed: String = ""
    @State private var typingTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(displayed.isEmpty ? " " : displayed)
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
                try? await Task.sleep(nanoseconds: 22_000_000)
            }
        }
    }
}

// MARK: - Glass Spinner (preserved)

struct GlassSpinner: View {
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.08)
                .ignoresSafeArea()

            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color(white: 0.82), lineWidth: 0.75)

                Circle()
                    .trim(from: 0, to: 0.72)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.42, blue: 0.28).opacity(0.9),
                                Color(red: 1.0, green: 0.42, blue: 0.28).opacity(0.1)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .frame(width: 22, height: 22)
                    .rotationEffect(.degrees(rotation))
            }
            .frame(width: 60, height: 60)
            .shadow(color: .black.opacity(0.08), radius: 16, y: 4)
        }
        .onAppear {
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// MARK: - Step 1: Welcome

private struct LightWelcomeStepView: View {
    let onContinue: () -> Void
    let onLearnMore: () -> Void

    @State private var titleAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LightOnboardingContainer {
            VStack(spacing: 36) {
                // Large "B" glyph
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.42, blue: 0.28).opacity(0.14),
                                    Color(red: 0.58, green: 0.25, blue: 0.95).opacity(0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                        .overlay(Circle().stroke(Color(white: 0.86), lineWidth: 0.5))

                    Text("B")
                        .font(.system(size: 44, weight: .ultraLight, design: .serif))
                        .foregroundStyle(Color(white: 0.18))
                }
                .scaleEffect(titleAppeared ? 1.0 : (reduceMotion ? 1.0 : 0.80))
                .opacity(titleAppeared ? 1.0 : 0.0)

                // Title
                VStack(spacing: 12) {
                    Text("Study with\ndiscernment.")
                        .font(.system(size: 36, weight: .light, design: .serif))
                        .foregroundStyle(Color(white: 0.10))
                        .multilineTextAlignment(.center)
                        .scaleEffect(titleAppeared ? 1.0 : (reduceMotion ? 1.0 : 0.88))
                        .opacity(titleAppeared ? 1.0 : 0.0)
                        .padding(.horizontal, 28)

                    TypingText(
                        fullText: "Every answer is traceable to Scripture.\nBerean never guesses.",
                        delay: 0.55
                    )
                    .font(.custom("OpenSans-Regular", size: 17))
                    .foregroundStyle(Color(white: 0.45))
                    .lineSpacing(5)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                }

                Spacer().frame(height: 8)

                VStack(spacing: 12) {
                    LightPrimaryCTAButton(label: "Continue", isLoading: false, action: onContinue)

                    LightSecondaryCTAButton(label: "Learn how it works", action: onLearnMore)
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

private struct LightNotificationsStepView: View {
    let onAllow: () -> Void
    let onSkip: () -> Void

    @State private var isRequesting = false
    @State private var titleAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LightOnboardingContainer {
            VStack(spacing: 28) {
                Image(systemName: "bell")
                    .font(.system(size: 40, weight: .ultraLight))
                    .foregroundStyle(Color(white: 0.30))

                VStack(spacing: 12) {
                    Text("Stay in\nthe Word.")
                        .font(.system(size: 34, weight: .light, design: .serif))
                        .foregroundStyle(Color(white: 0.10))
                        .multilineTextAlignment(.center)
                        .scaleEffect(titleAppeared ? 1.0 : (reduceMotion ? 1.0 : 0.88))
                        .opacity(titleAppeared ? 1.0 : 0.0)
                        .padding(.horizontal, 28)

                    TypingText(
                        fullText: "Receive quiet reminders for your studies\nand prayers — nothing noisy, only depth.",
                        delay: 0.40
                    )
                    .font(.custom("OpenSans-Regular", size: 16))
                    .foregroundStyle(Color(white: 0.45))
                    .lineSpacing(5)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                }

                HStack(spacing: 7) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                    Text("Your attention is sacred. We'll always ask first.")
                        .font(.system(size: 12))
                }
                .foregroundStyle(Color(white: 0.55))
                .padding(.horizontal, 36)

                Spacer().frame(height: 4)

                VStack(spacing: 12) {
                    LightPrimaryCTAButton(
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

                    LightSecondaryCTAButton(label: "Not now", action: onSkip)
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

private struct LightMicrophoneStepView: View {
    let onEnable: () -> Void
    let onSkip: () -> Void

    @State private var isRequesting = false
    @State private var deniedTip = false
    @State private var micScale: CGFloat = 1.0
    @State private var titleAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LightOnboardingContainer {
            VStack(spacing: 28) {
                Image(systemName: "mic")
                    .font(.system(size: 44, weight: .ultraLight))
                    .foregroundStyle(Color(white: 0.30))
                    .scaleEffect(micScale)
                    .onAppear {
                        guard !reduceMotion else { return }
                        withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                            micScale = 1.04
                        }
                    }

                VStack(spacing: 12) {
                    Text("Speak\nyour question.")
                        .font(.system(size: 34, weight: .light, design: .serif))
                        .foregroundStyle(Color(white: 0.10))
                        .multilineTextAlignment(.center)
                        .scaleEffect(titleAppeared ? 1.0 : (reduceMotion ? 1.0 : 0.88))
                        .opacity(titleAppeared ? 1.0 : 0.0)
                        .padding(.horizontal, 28)

                    Text("Ask freely — while you pray, read, or walk.\nYour voice, your pace.")
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundStyle(Color(white: 0.45))
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                        .padding(.horizontal, 36)
                }

                if deniedTip {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                        Text("You can enable this later in Settings › Privacy › Microphone")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(Color(white: 0.50))
                    .padding(.horizontal, 36)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Spacer().frame(height: 4)

                VStack(spacing: 12) {
                    LightPrimaryCTAButton(
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

                    LightSecondaryCTAButton(label: "Skip", action: onSkip)
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

// MARK: - Focus Chip (adapted to light theme)

private struct LightFocusChip: View {
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
                withAnimation(.spring(response: 0.28, dampingFraction: 0.5)) { chipScale = 1.08 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) { chipScale = 1.0 }
                }
            }
            action()
        }) {
            Text(label)
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : Color(white: 0.35))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(
                    Group {
                        if isSelected {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 1.0, green: 0.48, blue: 0.30),
                                            Color(red: 0.95, green: 0.32, blue: 0.18)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        } else {
                            Capsule()
                                .fill(Color.white)
                                .overlay(Capsule().stroke(Color(white: 0.84), lineWidth: 0.75))
                        }
                    }
                )
                .shadow(
                    color: isSelected
                        ? Color(red: 1.0, green: 0.35, blue: 0.18).opacity(0.28)
                        : Color.black.opacity(0.05),
                    radius: 6,
                    y: 2
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(chipScale)
    }
}

// MARK: - Step 4: Personalization

private struct LightPersonalizationStepView: View {
    @Binding var selectedFoci: Set<String>
    @Binding var conciseMode: Bool
    let onStart: () -> Void

    private let foci = ["Bible Q&A", "Historical context", "Sermon notes", "Prayer help", "Life guidance"]

    @State private var titleAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasSelection: Bool { !selectedFoci.isEmpty }

    var body: some View {
        LightOnboardingContainer {
            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    Text("What matters\nmost to you?")
                        .font(.system(size: 32, weight: .light, design: .serif))
                        .foregroundStyle(Color(white: 0.10))
                        .multilineTextAlignment(.center)
                        .scaleEffect(titleAppeared ? 1.0 : (reduceMotion ? 1.0 : 0.88))
                        .opacity(titleAppeared ? 1.0 : 0.0)
                        .padding(.horizontal, 24)

                    Text("Berean will lean into these when you ask.")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(Color(white: 0.50))
                }

                // Chip grid
                FlowLayout(spacing: 10) {
                    ForEach(foci, id: \.self) { topic in
                        LightFocusChip(
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
                    Text("Prefer brief answers")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Color(white: 0.22))

                    Spacer()

                    Toggle("", isOn: $conciseMode)
                        .labelsHidden()
                        .tint(Color(red: 1.0, green: 0.42, blue: 0.28))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color(white: 0.88), lineWidth: 0.75)
                        )
                        .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)
                )
                .padding(.horizontal, 28)

                Spacer().frame(height: 4)

                LightPrimaryCTAButton(label: "Begin studying", isLoading: false, action: onStart)
                    .padding(.horizontal, 28)
                    .opacity(hasSelection ? 1.0 : 0.55)
                    .animation(.easeInOut(duration: 0.22), value: hasSelection)
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
