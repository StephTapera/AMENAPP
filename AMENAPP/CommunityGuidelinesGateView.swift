//
//  CommunityGuidelinesGateView.swift
//  AMENAPP
//
//  Premium liquid-glass floating card shown before posting.
//  Triggered by CommunityGuidelinesEligibilityService smart logic.
//
//  Design: Dimmed backdrop + centered glass card with staggered guideline rows.
//  Preserves the user's draft content — never clears compose state.
//

import SwiftUI

struct CommunityGuidelinesGateView: View {
    let onAccept: () -> Void
    let onCancel: () -> Void

    @State private var showCard = false
    @State private var rowsVisible: [Bool]

    private let guidelines: [(icon: String, color: Color, title: String, body: String)] = [
        ("heart.fill",       .pink,   "Be kind",           "Treat everyone with respect and compassion."),
        ("hand.raised.fill", .orange, "No harassment",      "AMEN is a safe space — zero tolerance for hate."),
        ("text.bubble.fill", .blue,   "Authentic sharing",  "Share your genuine thoughts and experiences."),
        ("shield.fill",      .purple, "Protect privacy",    "Never share others' personal information."),
        ("flag.fill",        .red,    "Report what's wrong", "Use the report button for violations."),
    ]

    init(onAccept: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.onAccept = onAccept
        self.onCancel = onCancel
        _rowsVisible = State(initialValue: Array(repeating: false, count: 5))
    }

    var body: some View {
        ZStack {
            // Dimmed backdrop
            Color.black.opacity(showCard ? 0.35 : 0)
                .ignoresSafeArea()
                .onTapGesture {
                    // Dismiss on backdrop tap (acts as cancel)
                    dismissCard {
                        onCancel()
                    }
                }
                .animation(.easeOut(duration: 0.25), value: showCard)

            // Floating glass card
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.6))
                            .frame(width: 64, height: 64)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                            )

                        Image(systemName: "hands.sparkles.fill")
                            .font(.systemScaled(28, weight: .semibold))
                            .foregroundStyle(.black.opacity(0.7))
                    }

                    Text("Community Guidelines")
                        .font(AMENFont.bold(20))
                        .foregroundStyle(.primary)

                    Text("Please review before sharing")
                        .font(AMENFont.regular(14))
                        .foregroundStyle(.black.opacity(0.45))
                }
                .padding(.top, 24)
                .padding(.bottom, 16)

                // Guideline rows with staggered entrance
                VStack(spacing: 0) {
                    ForEach(Array(guidelines.enumerated()), id: \.offset) { index, guideline in
                        guidelineRow(guideline, visible: rowsVisible[index])

                        if index < guidelines.count - 1 {
                            Rectangle()
                                .fill(Color.black.opacity(0.05))
                                .frame(height: 0.5)
                                .padding(.leading, 50)
                        }
                    }
                }
                .padding(.horizontal, 4)

                // Buttons
                VStack(spacing: 10) {
                    Button {
                        CommunityGuidelinesEligibilityService.shared.acknowledgeGuidelines()
                        dismissCard {
                            onAccept()
                        }
                    } label: {
                        Text("I Understand — Continue")
                            .font(AMENFont.bold(15))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.black)
                            )
                            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button {
                        dismissCard {
                            onCancel()
                        }
                    } label: {
                        Text("Not now")
                            .font(AMENFont.regular(14))
                            .foregroundStyle(.black.opacity(0.4))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.top, 16)
                .padding(.bottom, 20)
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.92))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.7), Color.white.opacity(0.15)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
            )
            .shadow(color: .black.opacity(0.12), radius: 32, y: 12)
            .padding(.horizontal, 24)
            .scaleEffect(showCard ? 1 : 0.92)
            .offset(y: showCard ? 0 : 40)
            .opacity(showCard ? 1 : 0)
            .animation(Motion.adaptive(.spring(response: 0.42, dampingFraction: 0.82)), value: showCard)
        }
        .onAppear {
            // Entrance animation
            withAnimation {
                showCard = true
            }
            // Stagger guideline rows
            for index in guidelines.indices {
                let delay = 0.15 + Double(index) * 0.06
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.78))) {
                        rowsVisible[index] = true
                    }
                }
            }
        }
    }

    // MARK: - Guideline Row

    private func guidelineRow(_ guideline: (icon: String, color: Color, title: String, body: String), visible: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(guideline.color.opacity(0.10))
                    .frame(width: 32, height: 32)
                Image(systemName: guideline.icon)
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(guideline.color)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(guideline.title)
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(.black.opacity(0.8))
                Text(guideline.body)
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.black.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .opacity(visible ? 1 : 0)
        .offset(y: visible ? 0 : 8)
    }

    // MARK: - Dismiss

    private func dismissCard(completion: @escaping () -> Void) {
        withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.80))) {
            showCard = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            completion()
        }
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.1).ignoresSafeArea()
        CommunityGuidelinesGateView(
            onAccept: { dlog("Accepted") },
            onCancel: { dlog("Cancelled") }
        )
    }
}
