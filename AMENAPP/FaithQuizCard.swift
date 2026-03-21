// FaithQuizCard.swift
// AMENAPP
import SwiftUI

struct FaithQuizCard: View {
    let quizId: String
    let title: String
    let subtitle: String
    let icon: String
    let iconBgColor: Color
    let isCompleted: Bool
    let onTap: () -> Void

    @State private var isPressed = false
    @State private var liftOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(iconBgColor)
                            .frame(width: 36, height: 36)
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    // Completion badge
                    Text(isCompleted ? "✓ Done" : "New")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isCompleted ? Color(red: 0.09, green: 0.64, blue: 0.29) : Color(red: 0.85, green: 0.47, blue: 0.02))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(isCompleted ? Color(red: 0.09, green: 0.64, blue: 0.29).opacity(0.10) : Color(red: 0.85, green: 0.47, blue: 0.02).opacity(0.10))
                        .clipShape(Capsule())
                }
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
        .scaleEffect(reduceMotion ? 1.0 : (isPressed ? 0.95 : 1.0))
        .offset(y: reduceMotion ? 0 : liftOffset)
        .shadow(color: .black.opacity(isPressed ? 0.05 : 0.08), radius: isPressed ? 2 : 10, y: isPressed ? 1 : 5)
        .animation(.spring(response: 0.3, dampingFraction: 0.55), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) { isPressed = true }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
                        isPressed = false
                        if !reduceMotion { liftOffset = -5 }
                    }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.65).delay(0.12)) {
                        liftOffset = 0
                    }
                }
        )
    }
}
