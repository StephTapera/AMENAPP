// GroundingExerciseView.swift
// AMENAPP
//
// 5-4-3-2-1 grounding technique for anxiety relief.
// Each sense category presented one at a time with prompts.
// Writes HKCategorySample .mindfulSession to HealthKit on completion.
//

import SwiftUI
import HealthKit
import AVFoundation

struct GroundingExerciseView: View {
    @Environment(\.dismiss) private var dismiss

    private let healthStore = HKHealthStore()
    private let haptic = UIImpactFeedbackGenerator(style: .medium)
    private let synthesizer = AVSpeechSynthesizer()
    @AppStorage("groundingVoiceEnabled") private var voiceEnabled: Bool = true

    // Grounding steps: (count, sense, SF symbol, color, prompts)
    private let steps: [(Int, String, String, Color, [String])] = [
        (5, "SEE",   "eye.fill",         Color(red: 0.22, green: 0.52, blue: 0.50),
         ["Look around you. Name 5 things you can see.",
          "A color on the wall.", "Something that brings you peace.", "Light coming through a window.", "Something small you normally overlook."]),
        (4, "TOUCH", "hand.raised.fill",  Color(red: 0.52, green: 0.36, blue: 0.72),
         ["Notice 4 things you can physically feel.",
          "The ground beneath your feet.", "The texture of your clothing.", "The temperature of the air.", "Something in your hands right now."]),
        (3, "HEAR",  "ear.fill",          Color(red: 0.28, green: 0.38, blue: 0.62),
         ["Listen for 3 sounds in your environment.",
          "A distant sound outside.", "Sounds right here in the room.", "The rhythm of your own breathing."]),
        (2, "SMELL", "nose.fill",          Color(red: 0.22, green: 0.52, blue: 0.38),
         ["Notice 2 things you can smell.",
          "Something near you — food, fabric, air.", "Something further away, or a memory of a scent."]),
        (1, "TASTE", "mouth.fill",         Color(red: 0.72, green: 0.36, blue: 0.22),
         ["Notice 1 thing you can taste.",
          "Even just the inside of your mouth. Swallow slowly. You are here."]),
    ]

    @State private var stepIndex: Int = 0
    @State private var checkedCount: Int = 0
    @State private var appeared: Bool = false
    @State private var complete: Bool = false
    @State private var showCompletion: Bool = false

    private var currentStep: (Int, String, String, Color, [String]) { steps[stepIndex] }
    private var accent: Color { currentStep.3 }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.08, blue: 0.14), Color(red: 0.02, green: 0.05, blue: 0.10)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            if showCompletion {
                completionView.transition(.opacity)
            } else {
                mainView
            }
        }
        .animation(.easeInOut(duration: 0.35), value: showCompletion)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
            // Speak the first step prompt
            speakPrompt(currentStep.4.first ?? "")
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        .onDisappear {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    private var mainView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.1), in: Circle())
                }
                Spacer()
                // Step indicators
                HStack(spacing: 6) {
                    ForEach(0..<5, id: \.self) { i in
                        Circle()
                            .fill(i <= stepIndex ? steps[i].3 : Color.white.opacity(0.2))
                            .frame(width: 7, height: 7)
                    }
                }
                Spacer()
                // Voice toggle
                Button {
                    voiceEnabled.toggle()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.1), in: Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)

            Spacer()

            // Big count + sense
            VStack(spacing: 8) {
                Text("\(currentStep.0)")
                    .font(.system(size: 80, weight: .thin, design: .rounded))
                    .foregroundStyle(accent)
                Text("things you can \(currentStep.1)")
                    .font(.custom("OpenSans-SemiBold", size: 18))
                    .foregroundStyle(.white)
                Image(systemName: currentStep.2)
                    .font(.system(size: 28))
                    .foregroundStyle(accent.opacity(0.8))
                    .padding(.top, 4)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)

            Spacer()

            // Prompts / tap to check
            VStack(spacing: 10) {
                ForEach(0..<currentStep.4.count, id: \.self) { i in
                    let checked = i < checkedCount
                    Button {
                        guard i == checkedCount else { return }
                        haptic.impactOccurred()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            checkedCount += 1
                        }
                        if checkedCount >= currentStep.4.count {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                advanceStep()
                            }
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(checked ? accent : Color.white.opacity(0.1))
                                    .frame(width: 24, height: 24)
                                if checked {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            Text(currentStep.4[i])
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(checked ? .white.opacity(0.5) : .white.opacity(0.85))
                                .multilineTextAlignment(.leading)
                            Spacer()
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(checked ? accent.opacity(0.08) : Color.white.opacity(0.05))
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(i > checkedCount)
                }
            }
            .padding(.horizontal, 20)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: checkedCount)

            // Scripture anchor
            Text("\"Be still, and know that I am God.\" — Psalm 46:10")
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(.white.opacity(0.35))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 24)

            Spacer(minLength: 48)
        }
    }

    private var completionView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color(red: 0.22, green: 0.52, blue: 0.50))
            VStack(spacing: 8) {
                Text("You are grounded.")
                    .font(.custom("OpenSans-Bold", size: 24))
                    .foregroundStyle(.white)
                Text("You used all five of your senses to anchor yourself to this moment. That takes courage.")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Text("\"I sought the Lord and he answered me; he delivered me from all my fears.\" — Psalm 34:4")
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.white.opacity(0.45))
                .italic()
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Button { dismiss() } label: {
                Text("Done")
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color(red: 0.22, green: 0.52, blue: 0.50), in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 24)
            }
            Spacer()
        }
    }

    private func advanceStep() {
        if stepIndex < steps.count - 1 {
            withAnimation(.easeInOut(duration: 0.3)) {
                stepIndex += 1
                checkedCount = 0
                appeared = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeOut(duration: 0.4)) { appeared = true }
            }
            // Speak new step prompt + haptic pulse
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                speakPrompt(steps[stepIndex].4.first ?? "")
            }
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            speakPrompt("You are grounded. You used all five of your senses to anchor yourself to this moment.")
            Task { await writeHealthKit() }
            withAnimation { showCompletion = true }
        }
    }

    private func speakPrompt(_ text: String) {
        guard voiceEnabled, !text.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
        utterance.pitchMultiplier = 0.95
        utterance.preUtteranceDelay = 0.2
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }

    private func writeHealthKit() async {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKObjectType.categoryType(forIdentifier: .mindfulSession) else { return }
        do {
            try await healthStore.requestAuthorization(toShare: [type], read: [])
            let now = Date()
            let sample = HKCategorySample(type: type, value: HKCategoryValue.notApplicable.rawValue,
                                          start: now.addingTimeInterval(-180), end: now,
                                          metadata: ["AMENGrounding": "5-4-3-2-1"])
            try await healthStore.save(sample)
        } catch {
            dlog("⚠️ HealthKit grounding write failed: \(error.localizedDescription)")
        }
    }
}
