// BereanOnboardingView.swift
// AMEN App — Berean AI first-time onboarding flow (redesign).
// 4-screen TabView onboarding with liquid glass design.
// Uses @AppStorage("bereanOnboardingComplete") to gate display.
//
// NOTE: This file defines BereanFullOnboardingView and BereanOnboardingHost.
// The legacy BereanOnboardingView is in AMENAPP/BereanOnboardingView.swift (subdirectory).

import SwiftUI
import Foundation

// MARK: - Onboarding Host (gate view)

/// Drop this in your root content view instead of BereanAIAssistantView
/// to show onboarding on first launch.
struct BereanOnboardingHost: View {
    @AppStorage("bereanOnboardingComplete") private var onboardingComplete = false
    var onComplete: (() -> Void)? = nil

    var body: some View {
        if onboardingComplete {
            BereanHomeView()
        } else {
            BereanFullOnboardingView {
                onboardingComplete = true
                onComplete?()
            }
        }
    }
}

// MARK: - Focus Items (Step 3 personalization)

private let bereanFocusItems: [(label: String, icon: String)] = [
    ("Faith",       "cross"),
    ("Study",       "book.pages"),
    ("Work",        "briefcase"),
    ("Life",        "heart"),
    ("Creativity",  "paintbrush"),
    ("Building",    "hammer"),
]

// MARK: - BereanFullOnboardingView

/// 4-screen liquid glass onboarding. Presented only once, on first launch.
struct BereanFullOnboardingView: View {
    let onComplete: () -> Void

    @State private var currentPage: Int = 0
    @State private var selectedFocusItems: Set<String> = []
    @State private var circleScale: CGFloat = 1.0
    @State private var circleOpacity: Double = 1.0
    @State private var isTransitioning: Bool = false

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            // Background gradient orb — subtle ambient light
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.95), Color.white],
                        center: .topLeading,
                        startRadius: 20,
                        endRadius: 400
                    )
                )
                .frame(width: 600, height: 600)
                .offset(x: -100, y: -200)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Page dots
                pageDots
                    .padding(.top, 60)
                    .padding(.bottom, 20)

                // Page content
                TabView(selection: $currentPage) {
                    screen1.tag(0)
                    screen2.tag(1)
                    screen3.tag(2)
                    screen4.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.spring(response: 0.38, dampingFraction: 0.82), value: currentPage)

                // CTA button
                ctaButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 48)
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Page Dots

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(i == currentPage ? 0.75 : 0.18))
                    .frame(width: i == currentPage ? 22 : 8, height: 8)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
            }
        }
    }

    // MARK: - Screen 1: Identity

    private var screen1: some View {
        VStack(spacing: 0) {
            Spacer()

            // Liquid glass circle icon
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().fill(Color.white.opacity(0.72)))
                    .overlay(Circle().strokeBorder(BereanColor.glassStroke, lineWidth: 0.75))
                    .shadow(color: .black.opacity(0.07), radius: 20, x: 0, y: 8)
                    .frame(width: 110, height: 110)

                Image(systemName: "cross")
                    .font(.system(size: 38, weight: .light))
                    .foregroundColor(BereanColor.textPrimary)
            }
            .padding(.bottom, 36)

            Text("Berean")
                .font(BereanType.displayTitle())
                .foregroundColor(BereanColor.textPrimary)
                .padding(.bottom, 12)

            Text("Your AI companion for faith,\nstudy, and life.")
                .font(BereanType.headline())
                .foregroundColor(BereanColor.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Screen 2: What it does

    private var screen2: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Text("What Berean does")
                    .font(BereanType.sectionTitle())
                    .foregroundColor(BereanColor.textPrimary)
                    .padding(.bottom, 8)

                featureRow(
                    icon: "magnifyingglass.circle",
                    title: "Study the Bible deeply",
                    desc: "Context, cross-references, and theological insight on any passage."
                )
                featureRow(
                    icon: "brain.head.profile",
                    title: "Think through life decisions",
                    desc: "Grounded guidance for work, relationships, and personal choices."
                )
                featureRow(
                    icon: "heart.text.square",
                    title: "Pray and reflect with guidance",
                    desc: "Prayer prompts, devotionals, and reflective questions tailored to you."
                )
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private func featureRow(icon: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.72))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(BereanColor.glassStroke, lineWidth: 0.5)
                    )
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(BereanColor.textPrimary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(BereanType.subheadline())
                    .foregroundColor(BereanColor.textPrimary)
                Text(desc)
                    .font(BereanType.caption())
                    .foregroundColor(BereanColor.textSecondary)
                    .lineSpacing(3)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Screen 3: Choose your focus

    private var screen3: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                Text("What brings you here?")
                    .font(BereanType.sectionTitle())
                    .foregroundColor(BereanColor.textPrimary)

                Text("Choose what matters most to you.")
                    .font(BereanType.subheadline())
                    .foregroundColor(BereanColor.textSecondary)

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(bereanFocusItems, id: \.label) { item in
                        focusChip(item: item)
                    }
                }
                .padding(.top, 4)
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private func focusChip(item: (label: String, icon: String)) -> some View {
        let isSelected = selectedFocusItems.contains(item.label)
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                if isSelected {
                    selectedFocusItems.remove(item.label)
                } else {
                    selectedFocusItems.insert(item.label)
                }
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: item.icon)
                    .font(.system(size: 18, weight: .light))
                    .foregroundColor(isSelected ? Color.white : BereanColor.textPrimary)
                Text(item.label)
                    .font(BereanType.caption())
                    .foregroundColor(isSelected ? Color.white : BereanColor.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.black)
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.black : BereanColor.glassStroke,
                            lineWidth: isSelected ? 0 : 0.5
                        )
                )
                .shadow(
                    color: isSelected ? Color.black.opacity(0.16) : Color.clear,
                    radius: isSelected ? 8 : 0,
                    y: isSelected ? 4 : 0
                )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Screen 4: Ready

    private var screen4: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                // Expanding circle animation on this screen
                Circle()
                    .fill(Color(white: 0.96))
                    .frame(width: 120 * circleScale, height: 120 * circleScale)
                    .opacity(circleOpacity)
                    .scaleEffect(circleScale)

                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().fill(Color.white.opacity(0.72)))
                    .overlay(Circle().strokeBorder(BereanColor.glassStroke, lineWidth: 0.75))
                    .shadow(color: .black.opacity(0.07), radius: 20, x: 0, y: 8)
                    .frame(width: 110, height: 110)

                Image(systemName: "checkmark")
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(BereanColor.textPrimary)
            }
            .padding(.bottom, 36)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 2.5)
                        .repeatForever(autoreverses: true)
                ) {
                    circleScale = 1.18
                    circleOpacity = 0.0
                }
            }

            Text("You're all set.")
                .font(BereanType.displayTitle())
                .foregroundColor(BereanColor.textPrimary)
                .padding(.bottom, 12)

            Text("Berean is ready to help you grow.")
                .font(BereanType.headline())
                .foregroundColor(BereanColor.textSecondary)
                .multilineTextAlignment(.center)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - CTA Button

    private var ctaButton: some View {
        let isLastPage = currentPage == 3

        return Button {
            if isLastPage {
                saveFocusPreferences()
                withAnimation(.easeIn(duration: 0.35)) {
                    isTransitioning = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
                    UserDefaults.standard.set(true, forKey: "bereanOnboardingComplete")
                    onComplete()
                }
            } else {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    currentPage += 1
                }
            }
        } label: {
            Text(isLastPage ? "Start" : "Continue")
                .font(AMENFont.semiBold(17))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.black.clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous)))
                .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .opacity(isTransitioning ? 0 : 1)
        .animation(.easeIn(duration: 0.2), value: isTransitioning)
    }

    // MARK: - Helpers

    private func saveFocusPreferences() {
        guard !selectedFocusItems.isEmpty else { return }
        UserDefaults.standard.set(
            Array(selectedFocusItems),
            forKey: "bereanFocusPreferences"
        )
    }
}

// MARK: - Previews

struct BereanFullOnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        BereanFullOnboardingView(onComplete: {})
    }
}

struct BereanOnboardingHost_Previews: PreviewProvider {
    static var previews: some View {
        BereanOnboardingHost()
    }
}
