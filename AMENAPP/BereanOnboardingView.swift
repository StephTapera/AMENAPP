// BereanOnboardingView.swift
// AMENAPP — Berean Onboarding V3
// Production-ready 4-step onboarding with MVVM, persistence, analytics, and chat handoff.

import SwiftUI

// MARK: - Host

struct BereanOnboardingHost: View {
    @AppStorage("bereanOnboardingComplete") private var onboardingComplete = false
    var onComplete: (() -> Void)? = nil

    var body: some View {
        if onboardingComplete {
            BereanHomeView()
        } else {
            BereanOnboardingView {
                onboardingComplete = true
                onComplete?()
            }
        }
    }
}

// MARK: - View

struct BereanOnboardingView: View {
    @StateObject private var vm: BereanOnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(onComplete: @escaping () -> Void) {
        _vm = StateObject(wrappedValue: BereanOnboardingViewModel { _, _ in
            onComplete()
        })
    }

    init(onCompleteWithContext: @escaping (Set<BereanFocus>, BereanStarterContext) -> Void) {
        _vm = StateObject(wrappedValue: BereanOnboardingViewModel(onComplete: onCompleteWithContext))
    }

    var body: some View {
        GeometryReader { geometry in
            let horizontalPadding = geometry.size.width < 375 ? 18.0 : 24.0

            ZStack {
                onboardingBackground

                VStack(spacing: 0) {
                    headerBar
                        .padding(.top, geometry.safeAreaInsets.top + 12)
                        .padding(.horizontal, horizontalPadding)

                    BereanProgressPills(currentStep: vm.currentStep)
                        .padding(.top, 14)
                        .padding(.bottom, 18)
                        .padding(.horizontal, horizontalPadding)

                    ScrollView(showsIndicators: false) {
                        stepContent
                            .padding(.horizontal, horizontalPadding)
                            .padding(.bottom, 20)
                            .frame(maxWidth: 520)
                            .frame(maxWidth: .infinity)
                    }
                    .scrollBounceBehavior(.basedOnSize)

                    bottomCTAArea
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, 12)
                        .padding(.bottom, max(geometry.safeAreaInsets.bottom + 8, 24))
                        .background(
                            LinearGradient(
                                colors: [Color.white.opacity(0.0), Color.white.opacity(0.88), Color.white.opacity(0.96)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Background

    private var onboardingBackground: some View {
        ZStack {
            Color(white: 0.975)

            Circle()
                .fill(Color.black.opacity(0.035))
                .frame(width: 380, height: 380)
                .blur(radius: 50)
                .offset(x: -130, y: -260)

            RoundedRectangle(cornerRadius: 80, style: .continuous)
                .fill(Color.black.opacity(0.026))
                .frame(width: 300, height: 160)
                .blur(radius: 40)
                .rotationEffect(.degrees(-18))
                .offset(x: 110, y: 280)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Berean")
                    .font(BereanType.sectionTitle())
                    .foregroundStyle(BereanColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text(vm.currentStep.eyebrow)
                    .font(BereanType.caption())
                    .foregroundStyle(BereanColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            BereanStepBadge(current: vm.currentStep.analyticsIndex, total: BereanOnboardingStep.total)
        }
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        let transition: AnyTransition = reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.98)).combined(with: .offset(y: 12)),
                removal: .opacity.combined(with: .offset(y: -8))
            )

        Group {
            switch vm.currentStep {
            case .introduction:
                BereanStep1View(content: vm.content)
                    .id(BereanOnboardingStep.introduction)
            case .capabilities:
                BereanStep2View(content: vm.content)
                    .id(BereanOnboardingStep.capabilities)
            case .focus:
                BereanStep3View(
                    content: vm.content,
                    selectedFocuses: vm.selectedFocuses,
                    onToggle: vm.toggleFocus
                )
                .id(BereanOnboardingStep.focus)
            case .ready:
                BereanStep4View(
                    content: vm.content,
                    selectedFocuses: vm.selectedFocuses,
                    starterContext: vm.starterContext
                )
                .id(BereanOnboardingStep.ready)
            }
        }
        .transition(transition)
        .animation(reduceMotion ? .none : .spring(response: 0.42, dampingFraction: 0.86), value: vm.currentStep)
    }

    // MARK: - Bottom CTA

    private var bottomCTAArea: some View {
        VStack(spacing: 10) {
            Button(action: vm.continueTapped) {
                Text(vm.ctaTitle)
                    .opacity(vm.isCompleting ? 0.65 : 1)
            }
            .buttonStyle(BereanPrimaryCTAStyle())
            .disabled(vm.isCompleting)
            .accessibilityIdentifier(vm.isOnLastStep ? "berean_start_chat_button" : "berean_continue_button")

            HStack {
                Button(action: vm.backTapped) {
                    Text(vm.content.ctaBack)
                        .font(BereanType.caption())
                        .foregroundStyle(vm.canGoBack ? BereanColor.textPrimary : BereanColor.textSecondary.opacity(0.4))
                }
                .disabled(!vm.canGoBack)
                .accessibilityIdentifier("berean_back_button")

                Spacer()

                if !vm.isOnLastStep {
                    Button(action: vm.skipTapped) {
                        Text(vm.content.ctaSkip)
                            .font(BereanType.caption())
                            .foregroundStyle(BereanColor.textSecondary)
                    }
                    .accessibilityIdentifier("berean_skip_button")
                }
            }
            .frame(minHeight: 30)
        }
    }
}

// MARK: - Previews

#Preview("Default") {
    BereanOnboardingView { }
}

#Preview("iPhone SE") {
    BereanOnboardingView { }
}

#Preview("Large Type") {
    BereanOnboardingView { }
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Final Step") {
    BereanStep4View(
        content: BereanDefaultOnboardingContentProvider().content,
        selectedFocuses: [.faith, .study, .work],
        starterContext: BereanStarterContext.derive(from: [.faith, .study, .work])
    )
    .padding()
    .background(Color(white: 0.975))
}

typealias BereanFullOnboardingView = BereanOnboardingView
