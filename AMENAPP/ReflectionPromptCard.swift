//
//  ReflectionPromptCard.swift
//  AMENAPP
//
//  Card presenting a daily reflection prompt with completion animation.
//  Animation 3: Icon spins to checkmark with Firestore save on completion.
//

import SwiftUI

struct ReflectionPromptCard: View {
    let reflection: ReflectionPrompt
    var onComplete: () -> Void = {}

    @State private var isCompleted = false
    @State private var iconRotation: Double = 0
    @State private var showCheck = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.amenGold)

                Text("Daily Reflection")
                    .font(.custom("OpenSans-Bold", size: 12))
                    .foregroundStyle(Color.adaptiveTextSecondary)
                    .textCase(.uppercase)
                    .tracking(1)

                Spacer()

                if let scripture = reflection.scripture {
                    Text(scripture)
                        .font(.custom("OpenSans-SemiBold", size: 11))
                        .foregroundStyle(Color.amenScripture)
                }
            }

            // Prompt
            Text(reflection.prompt)
                .font(.custom("OpenSans-SemiBold", size: 16))
                .foregroundStyle(Color.adaptiveTextPrimary)
                .fixedSize(horizontal: false, vertical: true)

            // Category pill
            Text(reflection.category)
                .font(.custom("OpenSans-SemiBold", size: 11))
                .foregroundStyle(Color.adaptiveTextSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.adaptiveButtonTertiaryBackground)
                )

            // Complete button
            Button(action: completeReflection) {
                HStack(spacing: 8) {
                    ZStack {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 18))
                            .opacity(showCheck ? 0 : 1)
                            .rotationEffect(.degrees(iconRotation))

                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .opacity(showCheck ? 1 : 0)
                            .foregroundStyle(.amenSuccess)
                            .scaleEffect(showCheck ? 1.0 : 0.3)
                    }

                    Text(isCompleted ? "Reflected" : "I've reflected on this")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                }
                .foregroundStyle(isCompleted ? Color.amenSuccess : Color.adaptiveButtonPrimaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isCompleted ? Color.amenSuccess.opacity(0.12) : Color.adaptiveButtonPrimaryBackground)
                )
            }
            .buttonStyle(.plain)
            .disabled(isCompleted)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.adaptiveSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.adaptiveBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reflection prompt: \(reflection.prompt). \(isCompleted ? "Completed" : "Tap to mark as reflected")")
        .onAppear {
            isCompleted = reflection.isCompleted
            showCheck = reflection.isCompleted
        }
    }

    private func completeReflection() {
        guard !isCompleted else { return }

        if reduceMotion {
            isCompleted = true
            showCheck = true
        } else {
            // Spin the pencil icon
            withAnimation(.easeInOut(duration: 0.4)) {
                iconRotation = 360
            }
            // After spin, swap to checkmark
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    showCheck = true
                    isCompleted = true
                }
            }
        }

        onComplete()
    }
}

#Preview {
    VStack(spacing: 16) {
        ReflectionPromptCard(
            reflection: ReflectionPrompt(
                id: "r1",
                prompt: "What drew you to faith?",
                category: "Journey",
                scripture: "Jeremiah 29:13",
                isCompleted: false
            )
        )
        ReflectionPromptCard(
            reflection: ReflectionPrompt(
                id: "r2",
                prompt: "How has God challenged you this week?",
                category: "Growth",
                scripture: "James 1:2-4",
                isCompleted: true
            )
        )
    }
    .padding()
}
