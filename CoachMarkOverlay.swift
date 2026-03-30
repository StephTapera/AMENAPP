//
//  CoachMarkOverlay.swift
//  AMENAPP
//
//  Simple Instagram-style FTUE pager.
//  Full-screen slides, big icon, short text, dot indicators, tap Next or Skip.
//

import SwiftUI

struct CoachMarkOverlay: View {
    @ObservedObject var ftueManager: FTUEManager

    // Legacy params kept so the call site in ContentView compiles without changes.
    let postCardFrame: CGRect?
    let bereanButtonFrame: CGRect?

    @State private var slideIn = false

    var body: some View {
        ZStack {
            // Solid dimmed backdrop
            Color.black.opacity(0.88)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Skip button — top right
                HStack {
                    Spacer()
                    if !ftueManager.currentStep.isLastStep {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.easeOut(duration: 0.2)) { ftueManager.skipFTUE() }
                        } label: {
                            Text("Skip")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white.opacity(0.55))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                        .padding(.top, 8)
                        .padding(.trailing, 4)
                    }
                }

                Spacer()

                // Icon
                ZStack {
                    Circle()
                        .fill(iconBackground)
                        .frame(width: 96, height: 96)

                    Image(systemName: ftueManager.currentStep.icon)
                        .font(.system(size: 42, weight: .medium))
                        .foregroundStyle(.white)
                }
                .scaleEffect(slideIn ? 1 : 0.6)
                .opacity(slideIn ? 1 : 0)

                Spacer().frame(height: 32)

                // Title
                Text(ftueManager.currentStep.title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .opacity(slideIn ? 1 : 0)
                    .offset(y: slideIn ? 0 : 16)

                Spacer().frame(height: 14)

                // Description
                Text(ftueManager.currentStep.description)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .padding(.horizontal, 40)
                    .opacity(slideIn ? 1 : 0)
                    .offset(y: slideIn ? 0 : 16)

                Spacer()

                // Dot progress indicator
                HStack(spacing: 8) {
                    ForEach(CoachMarkStep.allCases, id: \.self) { step in
                        Capsule()
                            .fill(step == ftueManager.currentStep
                                  ? Color.white
                                  : Color.white.opacity(0.3))
                            .frame(
                                width: step == ftueManager.currentStep ? 22 : 7,
                                height: 7
                            )
                            .animation(.spring(response: 0.3, dampingFraction: 0.7),
                                       value: ftueManager.currentStep)
                    }
                }
                .opacity(slideIn ? 1 : 0)

                Spacer().frame(height: 28)

                // Primary button
                Button {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    advance()
                } label: {
                    Text(ftueManager.currentStep.primaryButtonText)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.white)
                        )
                        .padding(.horizontal, 32)
                }
                .buttonStyle(PressableButtonStyle())
                .opacity(slideIn ? 1 : 0)
                .offset(y: slideIn ? 0 : 24)

                Spacer().frame(height: 48)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                slideIn = true
            }
        }
    }

    // MARK: - Helpers

    private var iconBackground: LinearGradient {
        let colors: [Color]
        switch ftueManager.currentStep {
        case .openTable:
            colors = [Color(red: 0.25, green: 0.47, blue: 1.0),
                      Color(red: 0.15, green: 0.3, blue: 0.85)]
        case .prayer:
            colors = [Color(red: 0.6, green: 0.4, blue: 1.0),
                      Color(red: 0.45, green: 0.25, blue: 0.85)]
        case .bereanIntro:
            colors = [Color(red: 0.98, green: 0.72, blue: 0.18),
                      Color(red: 0.9, green: 0.55, blue: 0.1)]
        case .messages:
            colors = [Color(red: 0.25, green: 0.8, blue: 0.6),
                      Color(red: 0.15, green: 0.65, blue: 0.5)]
        }
        return LinearGradient(colors: colors,
                              startPoint: .topLeading,
                              endPoint: .bottomTrailing)
    }

    private func advance() {
        // Animate out, advance step, animate back in
        withAnimation(.easeIn(duration: 0.15)) { slideIn = false }
        let isLast = ftueManager.currentStep.isLastStep
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            ftueManager.nextStep()
            if !isLast {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    slideIn = true
                }
            }
        }
    }
}
