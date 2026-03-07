//
//  CommunityGuidelinesPrompt.swift
//  AMENAPP
//
//  Shown once on first post or first comment to reinforce community guidelines.
//  Uses UserDefaults to track whether the prompt has been shown.
//
//  Design: Liquid Glass — .ultraThinMaterial base, AMEN brand blue accent,
//  OpenSans typography, consistent with the rest of the app.
//

import SwiftUI

struct CommunityGuidelinesPrompt: View {
    @Environment(\.dismiss) var dismiss
    let onContinue: () -> Void

    private let guidelines: [(icon: String, color: Color, title: String, description: String)] = [
        ("heart.fill",       .pink,   "Be kind and respectful",  "Treat others as you'd want to be treated."),
        ("hand.raised.fill", .orange, "No harassment or hate",   "AMEN is a safe space for all believers."),
        ("text.bubble.fill", .blue,   "Authentic sharing",       "Share your own genuine thoughts and experiences."),
        ("shield.fill",      .purple, "Protect privacy",         "Don't share others' personal information."),
        ("flag.fill",        .red,    "Report what's wrong",     "Use the report button for guideline violations."),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient consistent with AMEN Liquid Glass
                LinearGradient(
                    colors: [Color(.systemBackground), Color.blue.opacity(0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        headerSection
                        guidelinesCard
                        continueButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 36)
                }
            }
            .navigationTitle("Community Guidelines")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 16) {
            // Icon with glass background
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 96, height: 96)
                    .overlay(
                        Circle()
                            .stroke(Color.blue.opacity(0.25), lineWidth: 1)
                    )
                    .shadow(color: Color.blue.opacity(0.15), radius: 20, x: 0, y: 8)

                Image(systemName: "hands.sparkles.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.blue, Color.blue.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .padding(.top, 24)

            VStack(spacing: 8) {
                Text("Welcome to AMEN")
                    .font(.custom("OpenSans-Bold", size: 26))
                    .multilineTextAlignment(.center)

                Text("Before you share your first post, please take a moment to review our Community Guidelines.")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Guidelines Card

    private var guidelinesCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(guidelines.enumerated()), id: \.offset) { index, guideline in
                guidelineRow(guideline)

                if index < guidelines.count - 1 {
                    Divider()
                        .padding(.leading, 52)
                        .opacity(0.5)
                }
            }
        }
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.primary.opacity(0.04), radius: 12, x: 0, y: 4)
    }

    private func guidelineRow(_ guideline: (icon: String, color: Color, title: String, description: String)) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(guideline.color.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: guideline.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(guideline.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(guideline.title)
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.primary)
                Text(guideline.description)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Continue Button

    private var continueButton: some View {
        Button {
            onContinue()
        } label: {
            HStack(spacing: 8) {
                Text("I Understand — Continue")
                    .font(.custom("OpenSans-Bold", size: 16))
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: [Color.blue, Color.blue.opacity(0.85)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .shadow(color: Color.blue.opacity(0.3), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

#Preview {
    CommunityGuidelinesPrompt {
        print("Continued")
    }
}
