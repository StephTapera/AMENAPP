// ReflectionPromptCard.swift
// AMENAPP
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Combine

struct ReflectionPromptCard: View {
    let promptId: String
    let promptText: String
    let isCompleted: Bool
    let onToggle: () async -> Void

    @State private var rotation: Double = 0
    @State private var localCompleted: Bool
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(promptId: String, promptText: String, isCompleted: Bool, onToggle: @escaping () async -> Void) {
        self.promptId = promptId
        self.promptText = promptText
        self.isCompleted = isCompleted
        self.onToggle = onToggle
        _localCompleted = State(initialValue: isCompleted)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Left accent bar
            Rectangle()
                .fill(Color(red: 0.71, green: 0.33, blue: 0.04))
                .frame(width: 3)
                .cornerRadius(1.5)

            // Prompt text
            Text(promptText)
                .font(.system(size: 12).italic())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Toggle button
            Button {
                guard !isAnimating else { return }
                isAnimating = true
                if !reduceMotion {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { rotation += 360 }
                }
                localCompleted.toggle()
                Task {
                    await onToggle()
                    isAnimating = false
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(localCompleted ? Color(red: 0.09, green: 0.64, blue: 0.29).opacity(0.12) : Color(.secondarySystemBackground))
                        .frame(width: 28, height: 28)
                    Image(systemName: localCompleted ? "checkmark" : "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(localCompleted ? Color(red: 0.09, green: 0.64, blue: 0.29) : Color(red: 0.71, green: 0.33, blue: 0.04))
                        .rotationEffect(.degrees(rotation))
                        .scaleEffect(localCompleted ? 1.15 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.55), value: localCompleted)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(localCompleted ? Color(red: 0.98, green: 1.0, blue: 0.97) : Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .cornerRadius(14)
        .animation(.easeOut(duration: 0.3), value: localCompleted)
    }
}
