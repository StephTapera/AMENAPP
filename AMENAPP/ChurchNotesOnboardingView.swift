//
//  ChurchNotesOnboardingView.swift
//  AMENAPP
//
//  Smart single-page onboarding for Church Notes feature
//  Liquid Glass design with premium animations
//

import SwiftUI

struct ChurchNotesOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("hasSeenChurchNotesOnboarding") private var hasSeenOnboarding = false
    @State private var showContent = false
    @State private var pulseAnimation = false

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
            liquidBackground

            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        heroSection

                        VStack(spacing: 12) {
                            ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                                ChurchNotesGlassFeaturePill(feature: feature, index: index)
                                    .opacity(showContent ? 1 : 0)
                                    .offset(y: showContent ? 0 : 22)
                                    .animation(
                                        Motion.adaptive(.spring(response: 0.56, dampingFraction: 0.84))
                                            .delay(0.16 + Double(index) * 0.07),
                                        value: showContent
                                    )
                            }
                        }
                        .padding(.horizontal, 20)

                        actionStack
                            .opacity(showContent ? 1 : 0)
                            .offset(y: showContent ? 0 : 18)
                            .animation(Motion.adaptive(.spring(response: 0.56, dampingFraction: 0.84)).delay(0.48), value: showContent)
                            .padding(.top, 6)
                            .padding(.bottom, 28)
                    }
                    .padding(.top, 18)
                }
            }
        }
        .onAppear {
            pulseAnimation = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                showContent = true
            }
        }
    }

    private var header: some View {
        HStack {
            Spacer()

            Button {
                skipOnboarding()
            } label: {
                Label("Skip", systemImage: "xmark")
                    .labelStyle(.titleAndIcon)
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.black.opacity(0.72))
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .amenLiquidGlassCapsuleSurface(isSelected: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Skip Church Notes onboarding")
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    private var heroSection: some View {
        VStack(spacing: 14) {
            ZStack {
                Image(systemName: "note.text")
                    .font(.systemScaled(42, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 104, height: 104)
                    .amenLiquidGlassCapsuleSurface(isSelected: true)

                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.42), lineWidth: 1)
                    .frame(width: 116, height: 116)
                    .scaleEffect(reduceMotion ? 1 : (pulseAnimation ? 1.08 : 0.96))
                    .opacity(reduceMotion ? 0.35 : (pulseAnimation ? 0.18 : 0.44))
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                        value: pulseAnimation
                    )
            }
            .padding(.top, 20)

            VStack(spacing: 6) {
                Text("Welcome to")
                    .font(.custom("OpenSans-Regular", size: 18))
                    .foregroundStyle(.black.opacity(0.58))

                Text("Church Notes")
                    .font(.custom("OpenSans-Bold", size: 42))
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                    .foregroundStyle(.black)

                Text("Capture and share your spiritual insights")
                    .font(.custom("OpenSans-Regular", size: 16))
                    .foregroundStyle(.black.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 28)
            }
        }
        .opacity(showContent ? 1 : 0)
        .offset(y: showContent ? 0 : 18)
        .animation(Motion.adaptive(.spring(response: 0.6, dampingFraction: 0.84)).delay(0.06), value: showContent)
    }

    private var actionStack: some View {
        VStack(spacing: 12) {
            ChurchNotesPrimaryGlassPillButton(title: "Get Started", systemImage: "arrow.right") {
                getStarted()
            }

            Button {
                skipOnboarding()
            } label: {
                Text("I'll explore on my own")
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .foregroundStyle(.black.opacity(0.62))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .amenLiquidGlassCapsuleSurface(isSelected: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Explore Church Notes without onboarding")
        }
        .padding(.horizontal, 20)
    }

    private var liquidBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.97, blue: 0.97),
                    Color(red: 0.91, green: 0.94, blue: 0.93),
                    Color(red: 0.97, green: 0.96, blue: 0.93)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.28)
                .blendMode(.softLight)
        }
        .ignoresSafeArea()
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

private struct ChurchNotesGlassFeaturePill: View {
    let feature: ChurchNotesFeature
    let index: Int

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: feature.icon)
                .font(.systemScaled(22, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 54, height: 54)
                .amenLiquidGlassCapsuleSurface(isSelected: false)

            VStack(alignment: .leading, spacing: 5) {
                Text(feature.title)
                    .font(.custom("OpenSans-Bold", size: 17))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(feature.description)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.black.opacity(0.68))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .amenLiquidGlassCapsuleSurface(isSelected: index == 0)
        .accessibilityElement(children: .combine)
    }
}

private struct ChurchNotesPrimaryGlassPillButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 17))
                    .lineLimit(1)

                Image(systemName: systemImage)
                    .font(.systemScaled(17, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background {
                Capsule(style: .continuous)
                    .fill(.black.opacity(isPressed ? 0.88 : 0.96))
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.22), Color.white.opacity(0.04)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.32), lineWidth: 0.7)
            }
            .shadow(color: .black.opacity(isPressed ? 0.08 : 0.18), radius: isPressed ? 8 : 18, x: 0, y: isPressed ? 4 : 10)
            .scaleEffect(reduceMotion ? 1 : (isPressed ? 0.985 : 1))
        }
        .buttonStyle(.plain)
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, state, _ in
                    state = true
                }
        )
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.24, dampingFraction: 0.84), value: isPressed)
        .accessibilityLabel(title)
    }
}

private struct ChurchNotesFeature {
    let icon: String
    let title: String
    let description: String
}

#Preview {
    ChurchNotesOnboardingView()
}
