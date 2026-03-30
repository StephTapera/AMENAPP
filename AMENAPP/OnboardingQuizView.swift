// OnboardingQuizView.swift
// AMEN App — Smart Onboarding Quiz
// 3-question quiz → personalized feed + welcome experience

import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth

// ─── MARK: Response Model ────────────────────────────────────────

struct OnboardingResult: Decodable {
    let welcomeMessage: String
    let feedTopics: [String]
    let firstVerse: FirstVerse
    let suggestedActions: [String]
    let firstChallenge: FirstChallenge
    let communityNote: String

    struct FirstVerse: Decodable {
        let reference: String
        let verse: String
        let personalNote: String
    }
    struct FirstChallenge: Decodable {
        let title: String
        let description: String
        let why: String
    }
}

// ─── MARK: Quiz Data ─────────────────────────────────────────────

struct QuizQuestion {
    let title: String
    let subtitle: String
    let options: [QuizOption]
}

struct QuizOption: Identifiable {
    let id = UUID()
    let emoji: String
    let label: String
    let value: String
}

private let quizQuestions: [QuizQuestion] = [
    QuizQuestion(
        title: "What are you walking through right now?",
        subtitle: "Be honest. This shapes everything.",
        options: [
            QuizOption(emoji: "🔥", label: "Building something", value: "building a business or pursuing a big goal"),
            QuizOption(emoji: "💔", label: "Healing & recovery", value: "healing from loss, heartbreak, or a hard season"),
            QuizOption(emoji: "🔍", label: "Searching for purpose", value: "searching for purpose, direction, and clarity"),
            QuizOption(emoji: "⚡", label: "Growth mode", value: "actively growing spiritually and personally"),
        ]
    ),
    QuizQuestion(
        title: "How long have you been walking in faith?",
        subtitle: "No wrong answer here.",
        options: [
            QuizOption(emoji: "🌱", label: "Just exploring", value: "just starting to explore faith and spirituality"),
            QuizOption(emoji: "📖", label: "New believer", value: "a new believer in the last 1-2 years"),
            QuizOption(emoji: "🏃", label: "Growing steadily", value: "a growing believer walking with God for several years"),
            QuizOption(emoji: "🏛", label: "Deeply rooted", value: "deeply rooted in faith and scripture for many years"),
        ]
    ),
    QuizQuestion(
        title: "What do you need most right now?",
        subtitle: "AMEN will build your experience around this.",
        options: [
            QuizOption(emoji: "🧠", label: "Wisdom", value: "wisdom and clarity for decisions and direction"),
            QuizOption(emoji: "🤝", label: "Community", value: "community, belonging, and people who understand me"),
            QuizOption(emoji: "☮️", label: "Peace", value: "peace, stillness, and emotional healing"),
            QuizOption(emoji: "💡", label: "Strategy", value: "strategy, tools, and intelligence to build my life and business"),
        ]
    )
]

// ─── MARK: ViewModel ─────────────────────────────────────────────

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var currentStep: Int = 0
    @Published var answers: [Int: QuizOption] = [:]
    @Published var userName: String = ""
    @Published var isLoading: Bool = false
    @Published var result: OnboardingResult?
    @Published var onboardingComplete: Bool = false

    private let db = Firestore.firestore()
    private var userId: String = Auth.auth().currentUser?.uid ?? "demo_user"

    var canAdvance: Bool { answers[currentStep] != nil }
    var isOnLastQuestion: Bool { currentStep == quizQuestions.count - 1 }

    func selectOption(_ option: QuizOption) {
        answers[currentStep] = option
    }

    func advance() {
        if currentStep < quizQuestions.count - 1 {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                currentStep += 1
            }
        } else {
            generatePersonalization()
        }
    }

    func generatePersonalization() {
        guard
            let season = answers[0]?.value,
            let faith  = answers[1]?.value,
            let need   = answers[2]?.value
        else { return }

        isLoading = true

        Task {
            do {
                let prompt = BereanPrompts.onboardingPersonalizer(
                    season: season,
                    faithStage: faith,
                    need: need,
                    name: userName.isEmpty ? "friend" : userName
                )
                let res = try await ClaudeAPIService.shared.completeJSON(
                    system: prompt,
                    userMessage: "Generate my personalized AMEN experience.",
                    as: OnboardingResult.self,
                    maxTokens: 1500
                )
                result = res
                saveToFirestore(result: res)
            } catch {
                print("Onboarding error: \(error)")
            }
            isLoading = false
        }
    }

    private func saveToFirestore(result: OnboardingResult) {
        db.collection("users").document(userId).setData([
            "feedTopics": result.feedTopics,
            "faithStage": answers[1]?.value ?? "",
            "currentSeason": answers[0]?.value ?? "",
            "primaryNeed": answers[2]?.value ?? "",
            "name": userName,
            "onboardingComplete": true,
            "onboardedAt": Timestamp()
        ], merge: true)
    }
}

// ─── MARK: Main View ─────────────────────────────────────────────

struct OnboardingQuizView: View {
    @StateObject private var vm = OnboardingViewModel()

    var body: some View {
        ZStack {
            Color(hex: "080810").ignoresSafeArea()

            if vm.isLoading {
                QuizPersonalizingView()
            } else if let result = vm.result {
                WelcomeResultView(result: result, userName: vm.userName) {
                    vm.onboardingComplete = true
                }
            } else {
                quizFlow
            }
        }
        .animation(.easeInOut(duration: 0.3), value: vm.currentStep)
        .animation(.easeInOut(duration: 0.4), value: vm.isLoading)
        .animation(.easeInOut(duration: 0.4), value: vm.result != nil)
    }

    private var quizFlow: some View {
        VStack(spacing: 0) {
            progressBar

            ScrollView {
                VStack(spacing: 32) {
                    nameField

                    let q = quizQuestions[max(0, vm.currentStep)]
                    VStack(spacing: 6) {
                        Text(q.title)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(q.subtitle)
                            .font(.system(size: 14))
                            .foregroundColor(Color.white.opacity(0.4))
                    }
                    .padding(.horizontal, 24)

                    VStack(spacing: 10) {
                        ForEach(q.options) { option in
                            QuizOptionCard(
                                option: option,
                                isSelected: vm.answers[vm.currentStep]?.id == option.id
                            ) {
                                vm.selectOption(option)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.top, 32)
                .padding(.bottom, 120)
            }

            VStack(spacing: 0) {
                Divider().background(Color.white.opacity(0.06))
                Button(action: vm.advance) {
                    HStack(spacing: 8) {
                        Text(vm.isOnLastQuestion ? "Personalize My Experience" : "Continue")
                            .font(.system(size: 16, weight: .semibold))
                        Image(systemName: vm.isOnLastQuestion ? "sparkles" : "arrow.right")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        vm.canAdvance
                        ? AnyView(LinearGradient(colors: [Color(hex: "C9A84C"), Color(hex: "F0D080")],
                                                  startPoint: .leading, endPoint: .trailing))
                        : AnyView(Color.white.opacity(0.1))
                    )
                    .cornerRadius(16)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .disabled(!vm.canAdvance)
            }
            .background(Color(hex: "080810").opacity(0.98))
        }
    }

    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(0..<quizQuestions.count, id: \.self) { i in
                Capsule()
                    .fill(i <= vm.currentStep
                          ? LinearGradient(colors: [Color(hex: "C9A84C"), Color(hex: "F0D080")],
                                           startPoint: .leading, endPoint: .trailing)
                          : LinearGradient(colors: [Color.white.opacity(0.12), Color.white.opacity(0.12)],
                                           startPoint: .leading, endPoint: .trailing))
                    .frame(height: 3)
                    .animation(.spring(response: 0.4), value: vm.currentStep)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var nameField: some View {
        if vm.currentStep == 0 {
            VStack(spacing: 8) {
                Text("First, what should we call you?")
                    .font(.system(size: 13))
                    .foregroundColor(Color.white.opacity(0.4))
                TextField("", text: $vm.userName,
                          prompt: Text("Your name").foregroundColor(Color.white.opacity(0.25)))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                    .padding(.horizontal, 40)
            }
        }
    }
}

// ─── MARK: Option Card ───────────────────────────────────────────

struct QuizOptionCard: View {
    let option: QuizOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(option.emoji)
                    .font(.system(size: 24))
                    .frame(width: 44, height: 44)
                    .background(isSelected ? Color(hex: "C9A84C").opacity(0.15) : Color.white.opacity(0.05))
                    .cornerRadius(12)

                Text(option.label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(isSelected ? .white : Color.white.opacity(0.7))

                Spacer()

                ZStack {
                    Circle()
                        .stroke(isSelected ? Color(hex: "C9A84C") : Color.white.opacity(0.2),
                                lineWidth: isSelected ? 2 : 0.5)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle().fill(Color(hex: "C9A84C")).frame(width: 12, height: 12)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(isSelected ? Color(hex: "C9A84C").opacity(0.08) : Color.white.opacity(0.04))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color(hex: "C9A84C").opacity(0.4) : Color.white.opacity(0.08),
                            lineWidth: isSelected ? 1 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.2, dampingFraction: 0.9), value: isSelected)
    }
}

// ─── MARK: Personalizing View ────────────────────────────────────

struct QuizPersonalizingView: View {
    @State private var pulseScale: CGFloat = 1.0
    let steps = ["Reading your answers...", "Finding your Scripture...", "Building your feed...", "Personalizing your experience..."]
    @State private var stepIndex = 0
    let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color(hex: "C9A84C").opacity(0.06))
                    .frame(width: 100, height: 100)
                    .scaleEffect(pulseScale)
                Circle()
                    .fill(LinearGradient(colors: [Color(hex: "C9A84C"), Color(hex: "F0D080")],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 64, height: 64)
                Text("✦").font(.system(size: 28)).foregroundColor(.black)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulseScale = 1.3
                }
            }

            VStack(spacing: 8) {
                Text("Berean AI is learning you...")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                Text(steps[stepIndex])
                    .font(.system(size: 14))
                    .foregroundColor(Color.white.opacity(0.45))
                    .animation(.easeInOut, value: stepIndex)
            }
            Spacer()
        }
        .onReceive(timer) { _ in stepIndex = (stepIndex + 1) % steps.count }
    }
}

// ─── MARK: Welcome Result View ───────────────────────────────────

struct WelcomeResultView: View {
    let result: OnboardingResult
    let userName: String
    let onComplete: () -> Void
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    Text("✦").font(.system(size: 36)).foregroundColor(Color(hex: "C9A84C"))

                    Text("Welcome\(userName.isEmpty ? "" : ", \(userName)")")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)

                    Text(result.welcomeMessage)
                        .font(.system(size: 15))
                        .foregroundColor(Color.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)
                .padding(.top, 40)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)

                // First verse
                VStack(alignment: .leading, spacing: 10) {
                    Text("YOUR FIRST WORD")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(hex: "C9A84C").opacity(0.7))
                        .kerning(2)
                    Text(result.firstVerse.reference)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "C9A84C"))
                    Text("\"\(result.firstVerse.verse)\"")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .lineSpacing(6)
                    Text(result.firstVerse.personalNote)
                        .font(.system(size: 13))
                        .foregroundColor(Color.white.opacity(0.5))
                        .lineSpacing(4)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "C9A84C").opacity(0.07))
                .cornerRadius(18)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(hex: "C9A84C").opacity(0.2), lineWidth: 0.5))
                .padding(.horizontal, 20)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)

                // First challenge
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("YOUR FIRST CHALLENGE")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color(hex: "22C55E").opacity(0.7))
                            .kerning(2)
                        Spacer()
                        Text("24 HRS")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "22C55E"))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color(hex: "22C55E").opacity(0.12))
                            .cornerRadius(8)
                    }
                    Text(result.firstChallenge.title).font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                    Text(result.firstChallenge.description)
                        .font(.system(size: 14)).foregroundColor(Color.white.opacity(0.65)).lineSpacing(4)
                    Text(result.firstChallenge.why)
                        .font(.system(size: 12)).foregroundColor(Color.white.opacity(0.35)).lineSpacing(3)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "22C55E").opacity(0.06))
                .cornerRadius(18)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(hex: "22C55E").opacity(0.15), lineWidth: 0.5))
                .padding(.horizontal, 20)

                Button(action: onComplete) {
                    HStack(spacing: 8) {
                        Text("Enter AMEN").font(.system(size: 16, weight: .bold))
                        Image(systemName: "arrow.right").font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(LinearGradient(colors: [Color(hex: "C9A84C"), Color(hex: "F0D080")],
                                               startPoint: .leading, endPoint: .trailing))
                    .cornerRadius(18)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
                appeared = true
            }
        }
    }
}
