//
//  LongitudinalOnboardingView.swift
//  AMENAPP
//
//  Full-screen onboarding flow for the "My Journey" longitudinal feature.
//  Presented as a fullScreenCover the first time the user opens the feature.
//

import SwiftUI

struct LongitudinalOnboardingView: View {

    @ObservedObject var vm: LongitudinalViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var currentPage = 0

    // MARK: - Page definitions

    private struct OnboardingPage {
        let icon: String
        let iconColor: Color
        let title: String
        let body: String
        let bullets: [String]
    }

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "figure.walk.motion",
            iconColor: Color.purple,
            title: "Your Spiritual Journey",
            body: "AMEN remembers where you've been. Your posts, prayers, and testimonies paint a picture of how God is shaping you.",
            bullets: []
        ),
        OnboardingPage(
            icon: "chart.line.uptrend.xyaxis",
            iconColor: Color(.sRGB, red: 0.96, green: 0.62, blue: 0.04, opacity: 1),
            title: "Growth, Mapped",
            body: "Our AI reads your content to find patterns of growth — seasons of doubt that became faith, isolation that became community.",
            bullets: [
                "Completely private by default",
                "You control what's shared",
                "Delete anytime"
            ]
        ),
        OnboardingPage(
            icon: "sparkles",
            iconColor: Color.purple,
            title: "Ready to Begin?",
            body: "Let AMEN analyze your content history and surface your story.",
            bullets: []
        )
    ]


    // MARK: - Body

    var body: some View {
        ZStack {
            ONB.canvas
                .ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Skip button (pages 0–1 only) ─────────────────────────
                HStack {
                    Spacer()
                    if currentPage < 2 {
                        Button("Skip") {
                            markSeenAndDismiss()
                        }
                        .font(AMENFont.medium(15))
                        .foregroundColor(ONB.inkTertiary)
                        .padding(.trailing, 24)
                        .padding(.top, 16)
                    } else {
                        Color.clear.frame(height: 44).padding(.top, 16)
                    }
                }
                .frame(height: 44)

                // ── Paged content ────────────────────────────────────────
                TabView(selection: $currentPage) {
                    ForEach(pages.indices, id: \.self) { index in
                        pageContent(pages[index], index: index)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: currentPage)

                // ── Page dots ────────────────────────────────────────────
                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == currentPage ? ONB.accent : ONB.inkTertiary.opacity(0.25))
                            .frame(width: index == currentPage ? 18 : 6, height: 5)
                            .animation(.spring(response: 0.35, dampingFraction: 0.80), value: currentPage)
                    }
                }
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Page Builder

    @ViewBuilder
    private func pageContent(_ page: OnboardingPage, index: Int) -> some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon
            Image(systemName: page.icon)
                .font(.systemScaled(88))
                .foregroundStyle(page.iconColor)
                .padding(.bottom, 36)

            // Title
            Text(page.title)
                .font(AMENFont.bold(26))
                .foregroundColor(ONB.inkPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
                .padding(.bottom, 14)

            // Body
            Text(page.body)
                .font(AMENFont.regular(15))
                .foregroundColor(ONB.inkSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 32)

            // Bullet list (page 1 only)
            if !page.bullets.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(page.bullets, id: \.self) { bullet in
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.systemScaled(15))
                                .foregroundColor(ONB.accentGold)
                            Text(bullet)
                                .font(AMENFont.regular(15))
                                .foregroundColor(ONB.inkSecondary)
                        }
                    }
                }
                .padding(.top, 24)
                .padding(.horizontal, 40)
            }

            Spacer()

            // ── CTA area ─────────────────────────────────────────────────
            VStack(spacing: 12) {
                if index < 2 {
                    ONBPrimaryButton(
                        title: "Next",
                        action: {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                                currentPage = index + 1
                            }
                        }
                    )
                    .padding(.horizontal, 32)
                } else {
                    ONBPrimaryButton(
                        title: "Enable My Journey",
                        action: {
                            Task { await vm.grantPermissionAndAnalyze() }
                            dismiss()
                        }
                    )
                    .padding(.horizontal, 32)

                    Button {
                        markSeenAndDismiss()
                    } label: {
                        Text("Maybe Later")
                            .font(AMENFont.medium(14))
                            .foregroundColor(ONB.inkTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 16)
        }
    }

    // MARK: - Helpers

    private func markSeenAndDismiss() {
        // Mark onboarding seen without granting permission
        UserDefaults.standard.set(true, forKey: "longitudinal_onboarding_seen")
        dismiss()
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Onboarding") {
    LongitudinalOnboardingView(vm: LongitudinalViewModel())
}
#endif
