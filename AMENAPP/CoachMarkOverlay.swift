//
//  CoachMarkOverlay.swift
//  AMENAPP
//
//  Single-screen FTUE showing community rules with animated list
//

import SwiftUI

struct CoachMarkOverlay: View {
    @ObservedObject var ftueManager: FTUEManager

    // Legacy params kept so the call site in ContentView compiles without changes.
    let postCardFrame: CGRect?
    let bereanButtonFrame: CGRect?

    @State private var slideIn = false
    @State private var animatedRules: [Bool] = Array(repeating: false, count: 6)

    var body: some View {
        ZStack {
            // Solid dimmed backdrop
            Color.black.opacity(0.92)
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer().frame(height: 60)

                    // Icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.pink, Color.pink.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)

                        Image(systemName: ftueManager.currentStep.icon)
                            .font(.systemScaled(36, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .scaleEffect(slideIn ? 1 : 0.6)
                    .opacity(slideIn ? 1 : 0)

                    Spacer().frame(height: 24)

                    // Title
                    Text(ftueManager.currentStep.title)
                        .font(.systemScaled(28, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .opacity(slideIn ? 1 : 0)
                        .offset(y: slideIn ? 0 : 16)

                    Spacer().frame(height: 12)

                    // Description
                    Text(ftueManager.currentStep.description)
                        .font(.systemScaled(15, weight: .regular))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 32)
                        .opacity(slideIn ? 1 : 0)
                        .offset(y: slideIn ? 0 : 16)

                    Spacer().frame(height: 32)

                    // Community Rules
                    VStack(alignment: .leading, spacing: 18) {
                        ruleItem(
                            index: 0,
                            icon: "heart.fill",
                            color: .pink,
                            title: "Love & Respect",
                            description: "Treat others with Christ-like love and respect, even when we disagree."
                        )

                        ruleItem(
                            index: 1,
                            icon: "checkmark.shield.fill",
                            color: .blue,
                            title: "Truth & Grace",
                            description: "Speak truth in love, avoiding gossip, slander, and false information."
                        )

                        ruleItem(
                            index: 2,
                            icon: "hands.sparkles.fill",
                            color: .purple,
                            title: "Encouragement",
                            description: "Build others up, not tear them down. Celebrate victories and support struggles."
                        )

                        ruleItem(
                            index: 3,
                            icon: "shield.lefthalf.filled",
                            color: .green,
                            title: "Safe Space",
                            description: "Help maintain a safe environment free from harassment, bullying, and hate speech."
                        )

                        ruleItem(
                            index: 4,
                            icon: "book.fill",
                            color: .orange,
                            title: "Biblical Integrity",
                            description: "Honor God's Word and not misrepresent Scripture or promote false teachings."
                        )

                        ruleItem(
                            index: 5,
                            icon: "person.3.fill",
                            color: .red,
                            title: "Community First",
                            description: "Report harmful content and trust the moderation team to keep our community safe."
                        )
                    }
                    .padding(.horizontal, 24)

                    Spacer().frame(height: 40)

                    // Primary button
                    Button {
                        print("🎯 FTUE Button tapped!")
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        ftueManager.nextStep()
                    } label: {
                        Text(ftueManager.currentStep.primaryButtonText)
                            .font(.systemScaled(17, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(.white)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 32)
                    .opacity(slideIn ? 1 : 0)
                    .offset(y: slideIn ? 0 : 24)

                    Spacer().frame(height: 40)
                }
                .padding(.bottom, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .allowsHitTesting(true)
        .onAppear {
            // Animate in header elements
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                slideIn = true
            }
            
            // Stagger animate rules
            for i in 0..<animatedRules.count {
                let delay = 0.3 + Double(i) * 0.08
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        animatedRules[i] = true
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func ruleItem(index: Int, icon: String, color: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.systemScaled(22))
                .foregroundColor(color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.systemScaled(16, weight: .semibold))
                    .foregroundColor(.white)

                Text(description)
                    .font(.systemScaled(14, weight: .regular))
                    .foregroundColor(.white.opacity(0.7))
                    .lineSpacing(3)
            }
        }
        .opacity(animatedRules[index] ? 1 : 0)
        .offset(x: animatedRules[index] ? 0 : -20)
    }
}

#Preview("FTUE Rules Screen") {
    CoachMarkOverlay(
        ftueManager: FTUEManager.shared,
        postCardFrame: nil,
        bereanButtonFrame: nil
    )
}
