// BreathingExerciseView.swift
// AMENAPP
//
// Clinical breathing exercise tool.
// Patterns: Box (4-4-4-4), 4-7-8, Diaphragmatic (5-5)
// - Animated circle expands/contracts with breath phases
// - Haptic UIImpactFeedbackGenerator pulses with breath guide
// - Optional AVSpeechSynthesizer voice cues
// - Writes HKCategoryTypeIdentifier.mindfulSession to HealthKit on completion
// - Post-exercise 1–5 mood check-in
//

import SwiftUI
import HealthKit
import AVFoundation

// MARK: - Breathing Pattern

enum BreathingPattern: String, CaseIterable {
    case box            = "Box Breathing"
    case fourSevenEight = "4-7-8 Breathing"
    case diaphragmatic  = "Diaphragmatic"

    var subtitle: String {
        switch self {
        case .box:            return "4-4-4-4 · Stress & focus"
        case .fourSevenEight: return "4-7-8 · Calm & sleep"
        case .diaphragmatic:  return "5-5 · Deep relaxation"
        }
    }

    var phases: [BreathPhase] { // ordered phases
        switch self {
        case .box:
            return [
                BreathPhase(label: "Inhale",  seconds: 4, isExpanding: true),
                BreathPhase(label: "Hold",    seconds: 4, isExpanding: nil),
                BreathPhase(label: "Exhale",  seconds: 4, isExpanding: false),
                BreathPhase(label: "Hold",    seconds: 4, isExpanding: nil),
            ]
        case .fourSevenEight:
            return [
                BreathPhase(label: "Inhale",  seconds: 4, isExpanding: true),
                BreathPhase(label: "Hold",    seconds: 7, isExpanding: nil),
                BreathPhase(label: "Exhale",  seconds: 8, isExpanding: false),
            ]
        case .diaphragmatic:
            return [
                BreathPhase(label: "Inhale",  seconds: 5, isExpanding: true),
                BreathPhase(label: "Exhale",  seconds: 5, isExpanding: false),
            ]
        }
    }

    var cycleDuration: Double {
        phases.map { Double($0.seconds) }.reduce(0, +)
    }

    var accentColor: Color {
        switch self {
        case .box:            return Color(red: 0.12, green: 0.52, blue: 0.50)
        case .fourSevenEight: return Color(red: 0.28, green: 0.38, blue: 0.62)
        case .diaphragmatic:  return Color(red: 0.22, green: 0.52, blue: 0.38)
        }
    }
}

struct BreathPhase {
    let label: String
    let seconds: Int
    let isExpanding: Bool? // nil = hold
}

// MARK: - Main View

struct BreathingExerciseView: View {
    @Environment(\.dismiss) private var dismiss

    // Settings
    @State private var selectedPattern: BreathingPattern = .box
    @State private var durationMinutes: Int = 3
    @State private var voiceEnabled: Bool = false

    // Session state
    @State private var isRunning: Bool = false
    @State private var currentPhaseIndex: Int = 0
    @State private var phaseSecondsRemaining: Int = 0
    @State private var totalSecondsElapsed: Int = 0
    @State private var sessionTask: Task<Void, Never>?

    // Animation
    @State private var circleScale: CGFloat = 0.5
    @State private var circleOpacity: Double = 0.6
    @State private var glowRadius: CGFloat = 0

    // Post-session
    @State private var sessionComplete: Bool = false
    @State private var moodRating: Int = 0
    @State private var showMoodCheck: Bool = false

    // HealthKit
    private let healthStore = HKHealthStore()

    // Haptics
    private let softHaptic  = UIImpactFeedbackGenerator(style: .soft)
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    private let heavyHaptic = UIImpactFeedbackGenerator(style: .medium)

    // Speech
    private let synth = AVSpeechSynthesizer()

    private var accent: Color { selectedPattern.accentColor }
    private var totalSeconds: Int { durationMinutes * 60 }
    private var currentPhase: BreathPhase { selectedPattern.phases[currentPhaseIndex] }
    private var progressFraction: Double { min(Double(totalSecondsElapsed) / Double(totalSeconds), 1.0) }

    var body: some View {
        ZStack {
            // Background — deep teal → near black
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.10, blue: 0.14), Color(red: 0.02, green: 0.06, blue: 0.10)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if showMoodCheck {
                moodCheckView
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else if isRunning || sessionComplete {
                sessionView
            } else {
                setupView
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showMoodCheck)
        .animation(.easeInOut(duration: 0.4), value: isRunning)
        .onDisappear {
            sessionTask?.cancel()
            synth.stopSpeaking(at: .immediate)
        }
    }

    // MARK: - Setup View

    private var setupView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.1), in: Circle())
                }
                Spacer()
                Text("Breathing")
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundStyle(.white)
                Spacer()
                Color.clear.frame(width: 36, height: 36)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)

            Spacer()

            // Pattern picker
            VStack(alignment: .leading, spacing: 12) {
                Text("PATTERN")
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(2)
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 24)

                VStack(spacing: 10) {
                    ForEach(BreathingPattern.allCases, id: \.self) { pattern in
                        Button {
                            selectedPattern = pattern
                            lightHaptic.impactOccurred()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(pattern.rawValue)
                                        .font(.custom("OpenSans-SemiBold", size: 15))
                                        .foregroundStyle(.white)
                                    Text(pattern.subtitle)
                                        .font(.custom("OpenSans-Regular", size: 12))
                                        .foregroundStyle(.white.opacity(0.55))
                                }
                                Spacer()
                                if selectedPattern == pattern {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(accent)
                                }
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(selectedPattern == pattern ? accent.opacity(0.18) : Color.white.opacity(0.07))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(selectedPattern == pattern ? accent.opacity(0.5) : Color.clear, lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal, 20)
                    }
                }
            }
            .padding(.top, 32)

            // Duration
            VStack(alignment: .leading, spacing: 12) {
                Text("DURATION")
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(2)
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 24)

                HStack(spacing: 10) {
                    ForEach([2, 3, 4, 5], id: \.self) { mins in
                        Button {
                            durationMinutes = mins
                            lightHaptic.impactOccurred()
                        } label: {
                            VStack(spacing: 2) {
                                Text("\(mins)")
                                    .font(.custom("OpenSans-Bold", size: 22))
                                    .foregroundStyle(durationMinutes == mins ? accent : .white.opacity(0.6))
                                Text("min")
                                    .font(.custom("OpenSans-Regular", size: 11))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(durationMinutes == mins ? accent.opacity(0.18) : Color.white.opacity(0.07))
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.top, 24)

            // Voice toggle
            HStack {
                Image(systemName: voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(voiceEnabled ? accent : .white.opacity(0.4))
                Text("Voice guidance")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Toggle("", isOn: $voiceEnabled)
                    .tint(accent)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            Spacer()

            // Start button
            Button { startSession() } label: {
                Text("Begin")
                    .font(.custom("OpenSans-SemiBold", size: 17))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(accent, in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Session View

    private var sessionView: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    sessionTask?.cancel()
                    isRunning = false
                    sessionComplete = false
                    currentPhaseIndex = 0
                    totalSecondsElapsed = 0
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                        Text("End")
                            .font(.custom("OpenSans-Regular", size: 14))
                    }
                    .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                // Progress time
                Text(timeString(totalSecondsElapsed))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 24)
            .padding(.top, 56)

            Spacer()

            // Animated circle
            ZStack {
                // Outer glow
                Circle()
                    .fill(accent.opacity(0.08))
                    .frame(width: 300, height: 300)
                    .scaleEffect(circleScale * 1.3)
                    .blur(radius: glowRadius)

                // Ripple ring
                Circle()
                    .stroke(accent.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 260, height: 260)
                    .scaleEffect(circleScale * 1.15)

                // Main breathing circle
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [accent.opacity(0.85), accent.opacity(0.35)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 100
                        )
                    )
                    .frame(width: 220, height: 220)
                    .scaleEffect(circleScale)
                    .opacity(circleOpacity)

                // Phase label + countdown
                VStack(spacing: 8) {
                    Text(sessionComplete ? "Complete" : currentPhase.label)
                        .font(.custom("OpenSans-SemiBold", size: sessionComplete ? 22 : 18))
                        .foregroundStyle(.white)
                    if !sessionComplete {
                        Text("\(phaseSecondsRemaining)")
                            .font(.system(size: 42, weight: .thin, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 36, weight: .thin))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            }

            Spacer()

            // Progress bar
            VStack(spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12)).frame(height: 4)
                        Capsule().fill(accent).frame(width: geo.size.width * progressFraction, height: 4)
                    }
                }
                .frame(height: 4)

                HStack {
                    Text(selectedPattern.rawValue)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                    Spacer()
                    Text("\(durationMinutes) min")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .padding(.horizontal, 36)

            if sessionComplete {
                Button {
                    withAnimation { showMoodCheck = true }
                } label: {
                    Text("How do you feel?")
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(accent, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Spacer(minLength: 48)
        }
    }

    // MARK: - Mood Check View

    private var moodCheckView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(accent)

                VStack(spacing: 8) {
                    Text("How are you feeling now?")
                        .font(.custom("OpenSans-SemiBold", size: 20))
                        .foregroundStyle(.white)
                    Text("After \(durationMinutes) min of \(selectedPattern.rawValue)")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.white.opacity(0.55))
                }

                HStack(spacing: 16) {
                    ForEach(1...5, id: \.self) { rating in
                        let labels = ["😔", "😐", "🙂", "😊", "😌"]
                        Button {
                            moodRating = rating
                            heavyHaptic.impactOccurred()
                            Task {
                                await writeHealthKitSession(durationMinutes: durationMinutes, moodRating: rating)
                                try? await Task.sleep(nanoseconds: 400_000_000)
                                dismiss()
                            }
                        } label: {
                            VStack(spacing: 6) {
                                Text(labels[rating - 1])
                                    .font(.system(size: 32))
                                Circle()
                                    .fill(moodRating == rating ? accent : Color.white.opacity(0.15))
                                    .frame(width: 8, height: 8)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.top, 8)

                Button {
                    Task {
                        await writeHealthKitSession(durationMinutes: durationMinutes, moodRating: 0)
                        dismiss()
                    }
                } label: {
                    Text("Skip")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.top, 4)
            }
            .padding(32)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    // MARK: - Session Logic

    private func startSession() {
        heavyHaptic.impactOccurred()
        currentPhaseIndex = 0
        totalSecondsElapsed = 0
        sessionComplete = false
        isRunning = true
        phaseSecondsRemaining = currentPhase.seconds
        animateToPhase(currentPhase)

        sessionTask = Task {
            while totalSecondsElapsed < totalSeconds && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    totalSecondsElapsed += 1
                    phaseSecondsRemaining -= 1
                    softHaptic.impactOccurred() // tick haptic

                    if phaseSecondsRemaining <= 0 {
                        // Advance phase
                        currentPhaseIndex = (currentPhaseIndex + 1) % selectedPattern.phases.count
                        phaseSecondsRemaining = currentPhase.seconds
                        animateToPhase(currentPhase)
                        if voiceEnabled { speak(currentPhase.label) }
                    }
                }
            }
            await MainActor.run {
                isRunning = false
                sessionComplete = true
                circleScale = 0.7
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }

        if voiceEnabled { speak(currentPhase.label) }
    }

    private func animateToPhase(_ phase: BreathPhase) {
        let duration = Double(phase.seconds)
        guard let expanding = phase.isExpanding else {
            // Hold — keep current scale, dim glow
            withAnimation(.easeInOut(duration: 0.3)) { glowRadius = 12 }
            return
        }
        let target: CGFloat = expanding ? 1.0 : 0.5
        let opacityTarget: Double = expanding ? 0.9 : 0.55
        withAnimation(.easeInOut(duration: duration)) {
            circleScale = target
            circleOpacity = opacityTarget
            glowRadius = expanding ? 28 : 8
        }
        lightHaptic.impactOccurred()
    }

    private func timeString(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private func speak(_ text: String) {
        synth.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.38
        utterance.pitchMultiplier = 0.9
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synth.speak(utterance)
    }

    // MARK: - HealthKit

    private func writeHealthKitSession(durationMinutes: Int, moodRating: Int) async {
        guard HKHealthStore.isHealthDataAvailable(),
              let mindfulType = HKObjectType.categoryType(forIdentifier: .mindfulSession) else { return }

        do {
            try await healthStore.requestAuthorization(toShare: [mindfulType], read: [])
            let now = Date()
            let start = now.addingTimeInterval(TimeInterval(-durationMinutes * 60))
            let sample = HKCategorySample(
                type: mindfulType,
                value: HKCategoryValue.notApplicable.rawValue,
                start: start,
                end: now,
                metadata: [
                    HKMetadataKeyExternalUUID: UUID().uuidString,
                    "AMENBreathingPattern": selectedPattern.rawValue,
                    "AMENMoodRating": moodRating
                ]
            )
            try await healthStore.save(sample)
            dlog("✅ HealthKit mindful session saved: \(durationMinutes) min, mood=\(moodRating)")
        } catch {
            dlog("⚠️ HealthKit write failed: \(error.localizedDescription)")
        }
    }
}
