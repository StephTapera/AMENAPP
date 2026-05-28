// BereanOnboardingComponents.swift
// AMENAPP — Berean Onboarding
// 3-page first-run flow + Welcome Back view.

import SwiftUI

// MARK: - Flow Container

struct BereanOnboardingFlowView: View {
    let onDismiss: () -> Void

    @State private var currentPage = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let analytics = BereanOnboardingDefaultAnalytics()

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                BereanOnboardingBackground()
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Top bar
                    HStack {
                        Text("Berean")
                            .font(BereanType.caption())
                            .foregroundStyle(BereanColor.textTertiary)
                            .accessibilityAddTraits(.isHeader)

                        Spacer()

                        if currentPage < 2 {
                            Button("Skip") { skip() }
                                .font(BereanType.caption())
                                .foregroundStyle(BereanColor.textSecondary)
                                .accessibilityLabel("Skip Berean introduction")
                                .accessibilityIdentifier("berean_onboarding_skip")
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, geo.safeAreaInsets.top + 16)
                    .padding(.bottom, 8)

                    // Paged content — swipe-enabled
                    TabView(selection: $currentPage) {
                        BereanPage1View()
                            .tag(0)
                        BereanPage2View()
                            .tag(1)
                        BereanPage3View()
                            .tag(2)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(maxHeight: .infinity)

                    // Bottom chrome: dots + CTA + back
                    VStack(spacing: 14) {
                        BereanDotIndicator(currentPage: currentPage, pageCount: 3)

                        Button(action: primaryAction) {
                            Text(currentPage == 2 ? "Begin" : "Continue")
                                .accessibilityLabel(currentPage == 2
                                    ? "Begin using Berean"
                                    : "Continue to next page")
                        }
                        .buttonStyle(BereanPrimaryCTAStyle())
                        .padding(.horizontal, 24)
                        .accessibilityIdentifier(currentPage == 2
                            ? "berean_begin_button"
                            : "berean_continue_button")

                        HStack {
                            if currentPage > 0 {
                                Button("Back") { goBack() }
                                    .font(BereanType.caption())
                                    .foregroundStyle(BereanColor.textSecondary)
                                    .accessibilityIdentifier("berean_onboarding_back")
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 28)
                        .frame(minHeight: 28)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, max(geo.safeAreaInsets.bottom + 8, 24))
                    .background(
                        LinearGradient(
                            colors: [
                                AmenTheme.Colors.backgroundPrimary.opacity(0),
                                AmenTheme.Colors.backgroundPrimary.opacity(0.96)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .allowsHitTesting(false)
                    )
                }
            }
            .ignoresSafeArea(edges: .all)
        }
        .onAppear {
            analytics.track(BereanOnboardingEvent.started, [:])
            trackPage(0)
            feedbackLight()
        }
        .onChange(of: currentPage) { _, page in
            trackPage(page)
            feedbackLight()
        }
    }

    // MARK: - Navigation

    private func primaryAction() {
        if currentPage == 2 { complete() } else { advance() }
    }

    private func advance() {
        withAnimation(reduceMotion ? .none : .spring(response: 0.38, dampingFraction: 0.82)) {
            currentPage = min(currentPage + 1, 2)
        }
    }

    private func goBack() {
        withAnimation(reduceMotion ? .none : .spring(response: 0.38, dampingFraction: 0.82)) {
            currentPage = max(currentPage - 1, 0)
        }
    }

    private func skip() {
        analytics.track(BereanOnboardingEvent.skipped, ["from_page": currentPage])
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        BereanOnboardingManager.shared.markComplete()
        onDismiss()
    }

    private func complete() {
        analytics.track(BereanOnboardingEvent.completed, [:])
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        BereanOnboardingManager.shared.markComplete()
        onDismiss()
    }

    private func trackPage(_ index: Int) {
        let name = BereanOnboardingPage(rawValue: index)?.analyticsName ?? "\(index)"
        analytics.track(BereanOnboardingEvent.pageViewed, ["page": name, "page_index": index])
    }

    private func feedbackLight() {
        guard !reduceMotion else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Shared Background

struct BereanOnboardingBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            AmenTheme.Colors.backgroundPrimary

            // Soft amenGold ambient glow — top-right
            Circle()
                .fill(AmenTheme.Colors.amenGold.opacity(scheme == .dark ? 0.06 : 0.11))
                .frame(width: 380, height: 380)
                .blur(radius: 90)
                .offset(x: 110, y: -300)
                .allowsHitTesting(false)

            // Soft purple ambient — bottom-left
            Circle()
                .fill(Color.purple.opacity(scheme == .dark ? 0.04 : 0.07))
                .frame(width: 300, height: 300)
                .blur(radius: 70)
                .offset(x: -130, y: 280)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Page 1: Meet Berean

struct BereanPage1View: View {
    @State private var orbAppeared = false
    @State private var textAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 32)

            // Hero: glass orb with gold glow
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                AmenTheme.Colors.amenGold.opacity(0.30),
                                AmenTheme.Colors.amenGold.opacity(0.08),
                                .clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 150
                        )
                    )
                    .frame(width: 300, height: 300)
                    .blur(radius: 18)
                    .opacity(orbAppeared ? 1 : 0)
                    .allowsHitTesting(false)

                BereanGlassOrb(icon: "sparkles", size: 180, iconSize: 56, pulse: true)
                    .scaleEffect(orbAppeared ? 1 : (reduceMotion ? 1 : 0.15))
                    .opacity(orbAppeared ? 1 : 0)
            }
            .accessibilityHidden(true)

            Spacer(minLength: 36)

            // Title + subtitle
            VStack(spacing: 14) {
                Text("Meet Berean.")
                    .font(.system(size: 38, weight: .bold, design: .default))
                    .foregroundStyle(BereanColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text("Your guide for Scripture\nand everyday faith.")
                    .font(BereanType.headline())
                    .foregroundStyle(BereanColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(textAppeared ? 1 : 0)
            .offset(y: textAppeared ? 0 : (reduceMotion ? 0 : 10))

            Spacer(minLength: 28)

            // Scripture citation
            VStack(spacing: 5) {
                Text("\u{201C}They examined the Scriptures daily.\u{201D}")
                    .font(.system(size: 15, weight: .regular).italic())
                    .foregroundStyle(BereanColor.textTertiary)
                    .multilineTextAlignment(.center)

                Text("— Acts 17:11")
                    .font(BereanType.micro())
                    .foregroundStyle(BereanColor.textTertiary)
            }
            .padding(.horizontal, 44)
            .opacity(textAppeared ? 1 : 0)

            Spacer(minLength: 100)
        }
        .padding(.horizontal, 28)
        .onAppear { startAnimations() }
    }

    private func startAnimations() {
        if reduceMotion {
            orbAppeared = true
            textAppeared = true
            return
        }
        withAnimation(.spring(response: 0.72, dampingFraction: 0.64)) {
            orbAppeared = true
        }
        withAnimation(.easeOut(duration: 0.48).delay(0.32)) {
            textAppeared = true
        }
    }
}

// MARK: - Page 2: How Berean Adapts

struct BereanPage2View: View {
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("Five modes.")
                        .font(.system(size: 34, weight: .bold, design: .default))
                        .foregroundStyle(BereanColor.textPrimary)
                        .accessibilityAddTraits(.isHeader)

                    Text("One guide.")
                        .font(.system(size: 28, weight: .regular, design: .default))
                        .foregroundStyle(BereanColor.textSecondary)
                }
                .multilineTextAlignment(.center)
                .padding(.top, 20)
                .padding(.bottom, 28)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : (reduceMotion ? 0 : 14))
                .animation(
                    reduceMotion ? .none : .easeOut(duration: 0.35),
                    value: appeared
                )

                VStack(spacing: 11) {
                    ForEach(Array(BereanMode.all.enumerated()), id: \.element.id) { index, mode in
                        BereanModeCard(mode: mode)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : (reduceMotion ? 0 : 18))
                            .animation(
                                reduceMotion
                                    ? .none
                                    : .spring(response: 0.46, dampingFraction: 0.80)
                                        .delay(0.08 + Double(index) * 0.07),
                                value: appeared
                            )
                    }
                }

                Spacer(minLength: 100)
            }
            .padding(.horizontal, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear {
            withAnimation(reduceMotion ? .none : .easeOut(duration: 0.25).delay(0.05)) {
                appeared = true
            }
        }
    }
}

struct BereanModeCard: View {
    let mode: BereanMode

    var body: some View {
        HStack(spacing: 14) {
            BereanGlassIconTile(icon: mode.systemIcon, size: 44, iconSize: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(mode.name)
                    .font(BereanType.headline())
                    .foregroundStyle(BereanColor.textPrimary)

                Text(mode.description)
                    .font(BereanType.subheadline())
                    .foregroundStyle(BereanColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .bereanGlassCard(cornerRadius: 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(mode.name): \(mode.description)")
    }
}

// MARK: - Page 3: Grounded & Trustworthy

struct BereanPage3View: View {
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)

            BereanGlassOrb(icon: "checkmark.shield", size: 148, iconSize: 46, pulse: false)
                .scaleEffect(appeared ? 1 : (reduceMotion ? 1 : 0.35))
                .opacity(appeared ? 1 : 0)
                .accessibilityHidden(true)

            Spacer(minLength: 36)

            VStack(spacing: 14) {
                Text("Grounded in truth.")
                    .font(.system(size: 34, weight: .bold, design: .default))
                    .foregroundStyle(BereanColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text("Berean cites Scripture and sources\nso you can examine for yourself.")
                    .font(BereanType.headline())
                    .foregroundStyle(BereanColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : (reduceMotion ? 0 : 10))

            Spacer(minLength: 28)

            VStack(spacing: 5) {
                Text("\u{201C}Test everything; hold fast what is good.\u{201D}")
                    .font(.system(size: 15, weight: .regular).italic())
                    .foregroundStyle(BereanColor.textTertiary)
                    .multilineTextAlignment(.center)

                Text("— 1 Thessalonians 5:21")
                    .font(BereanType.micro())
                    .foregroundStyle(BereanColor.textTertiary)
            }
            .padding(.horizontal, 36)
            .opacity(appeared ? 1 : 0)

            Spacer(minLength: 100)
        }
        .padding(.horizontal, 28)
        .onAppear {
            withAnimation(reduceMotion
                ? .none
                : .spring(response: 0.62, dampingFraction: 0.70).delay(0.06)) {
                appeared = true
            }
        }
    }
}

// MARK: - Welcome Back View

struct BereanWelcomeBackView: View {
    let onDismiss: () -> Void

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let analytics = BereanOnboardingDefaultAnalytics()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                BereanOnboardingBackground()
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    BereanGlassOrb(icon: "sun.horizon", size: 148, iconSize: 46, pulse: true)
                        .scaleEffect(appeared ? 1 : (reduceMotion ? 1 : 0.25))
                        .opacity(appeared ? 1 : 0)
                        .accessibilityHidden(true)

                    Spacer(minLength: 36)

                    VStack(spacing: 12) {
                        Text("Welcome back.")
                            .font(.system(size: 34, weight: .bold, design: .default))
                            .foregroundStyle(BereanColor.textPrimary)
                            .accessibilityAddTraits(.isHeader)

                        Text("Berean is ready to\nstudy with you again.")
                            .font(BereanType.headline())
                            .foregroundStyle(BereanColor.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : (reduceMotion ? 0 : 12))

                    Spacer()

                    Button(action: dismiss) {
                        Text("Continue")
                            .accessibilityLabel("Continue to Berean")
                    }
                    .buttonStyle(BereanPrimaryCTAStyle())
                    .padding(.horizontal, 24)
                    .padding(.bottom, max(geo.safeAreaInsets.bottom + 16, 36))
                    .opacity(appeared ? 1 : 0)
                    .accessibilityIdentifier("berean_welcome_back_continue")
                }
            }
        }
        .onAppear {
            analytics.track(BereanOnboardingEvent.welcomeBackShown, [:])
            withAnimation(reduceMotion
                ? .none
                : .spring(response: 0.66, dampingFraction: 0.72).delay(0.1)) {
                appeared = true
            }
            guard !reduceMotion else { return }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
    }

    private func dismiss() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        BereanOnboardingManager.shared.markWelcomeBackSeen()
        onDismiss()
    }
}

// MARK: - Dot Page Indicator

struct BereanDotIndicator: View {
    let currentPage: Int
    let pageCount: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<pageCount, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage
                          ? AmenTheme.Colors.iconPrimary.opacity(0.88)
                          : AmenTheme.Colors.iconSecondary.opacity(0.30))
                    .frame(width: index == currentPage ? 24 : 8, height: 6)
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: currentPage)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(currentPage + 1) of \(pageCount)")
        .accessibilityValue("Page \(currentPage + 1)")
    }
}

// MARK: - Debug Reset Banner

#if DEBUG
struct BereanOnboardingDebugBanner: View {
    var body: some View {
        Button("Reset Berean Onboarding (debug)") {
            BereanOnboardingManager.shared.resetForDebug()
        }
        .font(BereanType.caption())
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.85).clipShape(Capsule()))
    }
}
#endif
