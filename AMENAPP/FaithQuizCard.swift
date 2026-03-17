//
//  FaithQuizCard.swift
//  AMENAPP
//
//  Interactive quiz card with spring lift animation on press.
//  Animation 4: Options spring-lift on press with correct/incorrect feedback.
//

import SwiftUI

struct FaithQuizCard: View {
    let quiz: FaithQuiz
    var onAnswer: (Int) -> Void = { _ in }

    @State private var selectedAnswer: Int?
    @State private var isAnswered = false
    @State private var showExplanation = false
    @State private var pressedIndex: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.amenInfo)

                Text("Daily Quiz")
                    .font(.custom("OpenSans-Bold", size: 12))
                    .foregroundStyle(Color.adaptiveTextSecondary)
                    .textCase(.uppercase)
                    .tracking(1)

                Spacer()

                Text(quiz.scripture)
                    .font(.custom("OpenSans-SemiBold", size: 11))
                    .foregroundStyle(Color.amenScripture)
            }

            // Question
            Text(quiz.question)
                .font(.custom("OpenSans-SemiBold", size: 15))
                .foregroundStyle(Color.adaptiveTextPrimary)
                .fixedSize(horizontal: false, vertical: true)

            // Options
            VStack(spacing: 8) {
                ForEach(Array(quiz.options.enumerated()), id: \.offset) { index, option in
                    optionButton(index: index, text: option)
                }
            }

            // Explanation (shown after answering)
            if showExplanation {
                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                        .background(Color.adaptiveDivider)

                    HStack(spacing: 6) {
                        Image(systemName: selectedAnswer == quiz.correctIndex ? "checkmark.circle.fill" : "info.circle.fill")
                            .foregroundStyle(selectedAnswer == quiz.correctIndex ? Color.amenSuccess : Color.amenWarning)

                        Text(selectedAnswer == quiz.correctIndex ? "Correct!" : "Not quite")
                            .font(.custom("OpenSans-Bold", size: 13))
                            .foregroundStyle(selectedAnswer == quiz.correctIndex ? Color.amenSuccess : Color.amenWarning)
                    }

                    Text(quiz.explanation)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(Color.adaptiveTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
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
        .onAppear {
            if quiz.isAnswered {
                isAnswered = true
                selectedAnswer = quiz.userAnswer
                showExplanation = true
            }
        }
    }

    @ViewBuilder
    private func optionButton(index: Int, text: String) -> some View {
        let isSelected = selectedAnswer == index
        let isCorrect = index == quiz.correctIndex
        let showResult = isAnswered

        Button(action: {
            guard !isAnswered else { return }
            selectAnswer(index)
        }) {
            HStack(spacing: 10) {
                // Letter indicator
                Text(["A", "B", "C", "D"][index])
                    .font(.custom("OpenSans-Bold", size: 12))
                    .foregroundStyle(optionLetterColor(index: index, isSelected: isSelected, showResult: showResult, isCorrect: isCorrect))
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(optionLetterBackground(index: index, isSelected: isSelected, showResult: showResult, isCorrect: isCorrect))
                    )

                Text(text)
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundStyle(Color.adaptiveTextPrimary)

                Spacer()

                if showResult && isSelected {
                    Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(isCorrect ? Color.amenSuccess : Color.amenError)
                } else if showResult && isCorrect {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.amenSuccess)
                        .opacity(0.6)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(optionBackground(index: index, isSelected: isSelected, showResult: showResult, isCorrect: isCorrect))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(optionBorder(index: index, isSelected: isSelected, showResult: showResult, isCorrect: isCorrect), lineWidth: 1.5)
            )
            .scaleEffect(pressedIndex == index ? 0.97 : 1.0)
            .offset(y: pressedIndex == index ? 1 : 0)
        }
        .buttonStyle(.plain)
        .disabled(isAnswered)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isAnswered && !reduceMotion {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                            pressedIndex = index
                        }
                    }
                }
                .onEnded { _ in
                    if !reduceMotion {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                            pressedIndex = nil
                        }
                    }
                }
        )
        .accessibilityLabel("Option \(["A", "B", "C", "D"][index]): \(text)\(showResult && isCorrect ? ", correct answer" : "")\(showResult && isSelected && !isCorrect ? ", incorrect" : "")")
    }

    // MARK: - Styling Helpers

    private func optionLetterColor(index: Int, isSelected: Bool, showResult: Bool, isCorrect: Bool) -> Color {
        if showResult && isCorrect { return .white }
        if showResult && isSelected { return .white }
        return Color.adaptiveTextSecondary
    }

    private func optionLetterBackground(index: Int, isSelected: Bool, showResult: Bool, isCorrect: Bool) -> Color {
        if showResult && isCorrect { return Color.amenSuccess }
        if showResult && isSelected { return Color.amenError }
        return Color.adaptiveButtonTertiaryBackground
    }

    private func optionBackground(index: Int, isSelected: Bool, showResult: Bool, isCorrect: Bool) -> Color {
        if showResult && isCorrect { return Color.amenSuccess.opacity(0.08) }
        if showResult && isSelected && !isCorrect { return Color.amenError.opacity(0.08) }
        return Color.adaptiveButtonTertiaryBackground.opacity(0.5)
    }

    private func optionBorder(index: Int, isSelected: Bool, showResult: Bool, isCorrect: Bool) -> Color {
        if showResult && isCorrect { return Color.amenSuccess.opacity(0.4) }
        if showResult && isSelected && !isCorrect { return Color.amenError.opacity(0.4) }
        return Color.clear
    }

    // MARK: - Actions

    private func selectAnswer(_ index: Int) {
        selectedAnswer = index
        isAnswered = true

        if reduceMotion {
            showExplanation = true
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                showExplanation = true
            }
        }

        onAnswer(index)
    }
}

#Preview {
    VStack(spacing: 16) {
        FaithQuizCard(
            quiz: FaithQuiz(
                id: "q1",
                question: "Which book of the Bible begins with 'In the beginning'?",
                options: ["Exodus", "Genesis", "Psalms", "John"],
                correctIndex: 1,
                explanation: "Genesis 1:1 — 'In the beginning God created the heavens and the earth.'",
                scripture: "Genesis 1:1",
                isAnswered: false,
                userAnswer: nil
            )
        )
    }
    .padding()
}
