//
//  ChurchNotesOnboardingView.swift
//  AMENAPP
//
//  Smart single-page onboarding for Church Notes feature
//  Liquid Glass design with premium animations
//

import SwiftUI

struct ChurchNotesOnboardingView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("hasSeenChurchNotesOnboarding") private var hasSeenOnboarding = false
    @State private var currentFeature = 0
    @State private var showContent = false
    @State private var pulseAnimation = false
    @Namespace private var animation

    private let features: [ChurchNotesFeature] = [
        ChurchNotesFeature(
            icon: "note.text",
            title: "Create & Save Notes",
            description: "Capture sermon insights, reflections, and scriptures during church services"
        ),
        ChurchNotesFeature(
            icon: "square.and.arrow.up",
            title: "Share with Others",
            description: "Share your notes privately with friends or post to the community"
        ),
        ChurchNotesFeature(
            icon: "lightbulb.fill",
            title: "Post to OpenTable",
            description: "Share insights with the community - others can read, AMEN, and comment"
        ),
        ChurchNotesFeature(
            icon: "lock.fill",
            title: "Read-Only Protection",
            description: "Notes posted to OpenTable are protected - only you can edit your original"
        )
    ]

    var body: some View {
        ZStack {
            // Liquid Glass Background
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.96, blue: 0.96),
                    Color(red: 0.94, green: 0.94, blue: 0.94)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header with dismiss option
                HStack {
                    Spacer()

                    Button {
                        skipOnboarding()
                    } label: {
                        Text("Skip")
                            .font(.custom("OpenSans-SemiBold", size: 16))
                            .foregroundStyle(.black.opacity(0.6))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }

                ScrollView {
                    VStack(spacing: 32) {
                        // Hero Title Section
                        VStack(spacing: 12) {
                            // Animated Icon
                            ZStack {
                                // Pulsing background
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.black.opacity(0.08),
                                                Color.black.opacity(0.12)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 100, height: 100)
                                    .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                                    .opacity(pulseAnimation ? 0.8 : 1.0)
                                    .animation(
                                        .easeInOut(duration: 2.0)
                                        .repeatForever(autoreverses: true),
                                        value: pulseAnimation
                                    )

                                // Main icon
                                Image(systemName: "note.text")
                                    .font(.system(size: 44, weight: .semibold))
                                    .foregroundStyle(.black)
                            }
                            .padding(.top, 40)

                            Text("Welcome to")
                                .font(.custom("OpenSans-Regular", size: 18))
                                .foregroundStyle(.black.opacity(0.6))

                            Text("Church Notes")
                                .font(.custom("OpenSans-Bold", size: 42))
                                .foregroundStyle(.black)

                            Text("Capture and share your spiritual insights")
                                .font(.custom("OpenSans-Regular", size: 16))
                                .foregroundStyle(.black.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        .opacity(showContent ? 1 : 0)
                        .offset(y: showContent ? 0 : 20)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1), value: showContent)

                        // Features Grid
                        VStack(spacing: 20) {
                            ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                                FeatureCard(feature: feature, index: index)
                                    .opacity(showContent ? 1 : 0)
                                    .offset(y: showContent ? 0 : 30)
                                    .animation(
                                        .spring(response: 0.6, dampingFraction: 0.8)
                                        .delay(0.2 + Double(index) * 0.1),
                                        value: showContent
                                    )
                            }
                        }
                        .padding(.horizontal, 20)

                        // CTA Buttons
                        VStack(spacing: 16) {
                            // Primary CTA
                            Button {
                                getStarted()
                            } label: {
                                HStack(spacing: 8) {
                                    Text("Get Started")
                                        .font(.custom("OpenSans-Bold", size: 17))

                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(.black)
                                )
                            }
                            .padding(.horizontal, 20)
                            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)

                            // Secondary Option
                            Button {
                                skipOnboarding()
                            } label: {
                                Text("I'll explore on my own")
                                    .font(.custom("OpenSans-SemiBold", size: 15))
                                    .foregroundStyle(.black.opacity(0.5))
                            }
                        }
                        .opacity(showContent ? 1 : 0)
                        .offset(y: showContent ? 0 : 20)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.6), value: showContent)
                        .padding(.top, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .onAppear {
            pulseAnimation = true

            // Animate content after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showContent = true
            }
        }
    }

    private func getStarted() {
        hasSeenOnboarding = true
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        dismiss()
    }

    private func skipOnboarding() {
        hasSeenOnboarding = true
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        dismiss()
    }
}

// MARK: - Feature Card Component

private struct FeatureCard: View {
    let feature: ChurchNotesFeature
    let index: Int
    @State private var isPressed = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Icon Container
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.06),
                                Color.black.opacity(0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)

                Image(systemName: feature.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.black)
            }

            // Text Content
            VStack(alignment: .leading, spacing: 6) {
                Text(feature.title)
                    .font(.custom("OpenSans-Bold", size: 17))
                    .foregroundStyle(.black)

                Text(feature.description)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.black.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white)
                .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
                .shadow(color: .black.opacity(0.02), radius: 2, x: 0, y: 1)
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
    }
}

// MARK: - Supporting Models

private struct ChurchNotesFeature {
    let icon: String
    let title: String
    let description: String
}

// MARK: - Preview

#Preview {
    ChurchNotesOnboardingView()
}
