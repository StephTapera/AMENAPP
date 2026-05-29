//
//  CoachMarkOverlay.swift
//  AMENAPP
//
//  Liquid Glass FTUE — floating glass card over live feed content.
//  White base / black text / environmental backdrop bleed. No solid fills.
//

import SwiftUI

struct CoachMarkOverlay: View {
    @ObservedObject var ftueManager: FTUEManager

    // Legacy params — call site in ContentView compiles without changes.
    let postCardFrame: CGRect?
    let bereanButtonFrame: CGRect?

    @State private var cardOffset: CGFloat = 60
    @State private var cardOpacity: Double = 0
    @State private var backdropOpacity: Double = 0
    @State private var animatedRules: [Bool] = Array(repeating: false, count: 6)

    var body: some View {
        ZStack(alignment: .bottom) {
            // Subtle environmental dim — lets feed content bleed through
            Color.black.opacity(backdropOpacity * 0.35)
                .ignoresSafeArea()
                .onTapGesture { } // absorb taps outside card

            // Floating Liquid Glass card
            glassCard
                .offset(y: cardOffset)
                .opacity(cardOpacity)
        }
        .allowsHitTesting(true)
        .onAppear {
            withAnimation(.easeOut(duration: 0.22)) {
                backdropOpacity = 1
            }
            withAnimation(Motion.adaptive(.spring(response: 0.48, dampingFraction: 0.82))) {
                cardOffset = 0
                cardOpacity = 1
            }
            for i in 0..<animatedRules.count {
                let delay = 0.18 + Double(i) * 0.07
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(Motion.adaptive(.spring(response: 0.38, dampingFraction: 0.78))) {
                        animatedRules[i] = true
                    }
                }
            }
        }
    }

    // MARK: - Glass Card

    private var glassCard: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 20)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Icon badge
                    ZStack {
                        Circle()
                            .fill(.regularMaterial)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
                            )
                            .frame(width: 72, height: 72)
                            .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)

                        Image(systemName: ftueManager.currentStep.icon)
                            .font(.systemScaled(30, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                    }

                    Spacer().frame(height: 18)

                    // Title
                    Text(ftueManager.currentStep.title)
                        .font(.systemScaled(24, weight: .bold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)

                    Spacer().frame(height: 8)

                    // Subtitle
                    Text(ftueManager.currentStep.description)
                        .font(.systemScaled(14, weight: .regular))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 20)

                    Spacer().frame(height: 28)

                    // Divider
                    Rectangle()
                        .fill(Color.primary.opacity(0.07))
                        .frame(height: 1)
                        .padding(.horizontal, 4)

                    Spacer().frame(height: 20)

                    // Rules
                    VStack(alignment: .leading, spacing: 16) {
                        ruleRow(index: 0, icon: "heart.fill",          color: Color(red: 0.95, green: 0.26, blue: 0.35), title: "Love & Respect",      body: "Treat others with Christ-like love and respect, even when we disagree.")
                        ruleRow(index: 1, icon: "checkmark.shield.fill", color: Color(red: 0.20, green: 0.50, blue: 0.95), title: "Truth & Grace",       body: "Speak truth in love, avoiding gossip, slander, and false information.")
                        ruleRow(index: 2, icon: "hands.sparkles.fill",  color: Color(red: 0.55, green: 0.28, blue: 0.90), title: "Encouragement",       body: "Build others up, not tear them down. Celebrate victories and support struggles.")
                        ruleRow(index: 3, icon: "shield.lefthalf.filled", color: Color(red: 0.18, green: 0.70, blue: 0.45), title: "Safe Space",         body: "Help maintain a safe environment free from harassment, bullying, and hate speech.")
                        ruleRow(index: 4, icon: "book.fill",            color: Color(red: 0.95, green: 0.55, blue: 0.10), title: "Biblical Integrity",   body: "Honor God's Word and not misrepresent Scripture or promote false teachings.")
                        ruleRow(index: 5, icon: "person.3.fill",        color: Color(red: 0.90, green: 0.22, blue: 0.22), title: "Community First",      body: "Report harmful content and trust the moderation team to keep our community safe.")
                    }
                    .padding(.horizontal, 20)

                    Spacer().frame(height: 28)
                }
            }
            .scrollBounceBehavior(.basedOnSize)

            // CTA button
            Button {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.easeIn(duration: 0.15)) {
                    cardOpacity = 0
                    cardOffset = 40
                    backdropOpacity = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    ftueManager.nextStep()
                }
            } label: {
                Text(ftueManager.currentStep.primaryButtonText)
                    .font(.systemScaled(17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.primary)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            Spacer().frame(height: 16)
        }
        .background {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.65), Color.white.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.10), radius: 30, x: 0, y: -4)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 0)
    }

    // MARK: - Rule Row

    private func ruleRow(index: Int, icon: String, color: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.systemScaled(16, weight: .medium))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(body)
                    .font(.systemScaled(13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
        }
        .opacity(animatedRules[index] ? 1 : 0)
        .offset(y: animatedRules[index] ? 0 : 12)
    }
}

#Preview("FTUE — Liquid Glass") {
    ZStack {
        Color.gray.opacity(0.3).ignoresSafeArea()
        CoachMarkOverlay(
            ftueManager: FTUEManager.shared,
            postCardFrame: nil,
            bereanButtonFrame: nil
        )
    }
}
