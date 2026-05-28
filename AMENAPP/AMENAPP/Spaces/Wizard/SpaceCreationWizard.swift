// SpaceCreationWizard.swift
// AMENAPP — Spaces v2 Creation Wizard (Agent D)
//
// Full-screen Liquid Glass sheet (.presentationDetents: .large).
// 4-step state machine: .intent → .scaffold → .access → .confirm
//
// Entry point: SpaceCreationWizard(communityId:)
// Presented from SpacesRootView via .sheet(isPresented: $showCreationWizard).
//
// Step transitions: spring slide+fade (asymmetric: trailing-in / leading-out).
// X dismiss: top-right on .intent only.
// Back button: top-left on steps 2–4.
// Progress capsule: 4 dots at top.

import SwiftUI

struct SpaceCreationWizard: View {

    let communityId: String

    @StateObject private var viewModel = SpaceCreationViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                wizardToolbar

                progressIndicator
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                stepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                continueButtonArea
                    .padding(.horizontal, 20)
                    .padding(.bottom, 36)
                    .padding(.top, 8)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(viewModel.currentStep != .intent)
    }

    // MARK: - Toolbar

    private var wizardToolbar: some View {
        ZStack {
            HStack {
                if viewModel.currentStep != .intent {
                    Button {
                        withAnimation(stepTransitionAnimation) { viewModel.back() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Back")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Go back")
                    .transition(.opacity)
                } else {
                    Color.clear.frame(width: 60, height: 36)
                }

                Spacer()

                if viewModel.currentStep == .intent {
                    Button { dismiss() } label: {
                        ZStack {
                            Circle()
                                .fill(AmenTheme.Colors.surfaceChip)
                                .frame(width: 32, height: 32)
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AmenTheme.Colors.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                    .accessibilityHint("Closes the Space creation wizard.")
                    .transition(.opacity)
                } else {
                    Color.clear.frame(width: 32, height: 32)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .animation(reduceMotion ? .none : .spring(response: 0.3), value: viewModel.currentStep)

            Text(stepTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .padding(.top, 16)
        }
        .frame(minHeight: 52)
    }

    // MARK: - Progress indicator

    private var progressIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { idx in
                let isFilled = idx <= currentStepIndex
                Capsule(style: .continuous)
                    .fill(isFilled ? AmenTheme.Colors.amenGold : AmenTheme.Colors.surfaceChip)
                    .frame(width: isFilled ? 22 : 8, height: 6)
                    .animation(
                        reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.75),
                        value: viewModel.currentStep
                    )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(currentStepIndex + 1) of 4")
    }

    // MARK: - Step content

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.currentStep {
        case .intent:
            WizardIntentStep(viewModel: viewModel)
                .transition(stepTransition)
                .id("intent")
        case .scaffold:
            WizardScaffoldStep(viewModel: viewModel)
                .transition(stepTransition)
                .id("scaffold")
        case .access:
            WizardAccessStep(viewModel: viewModel)
                .transition(stepTransition)
                .id("access")
        case .confirm:
            WizardConfirmStep(
                viewModel: viewModel,
                communityId: communityId,
                onSuccess: { _ in dismiss() }
            )
            .transition(stepTransition)
            .id("confirm")
        }
    }

    // MARK: - Continue button area

    @ViewBuilder
    private var continueButtonArea: some View {
        switch viewModel.currentStep {
        case .intent, .access:
            primaryCTAButton
        case .scaffold:
            if viewModel.scaffoldError != nil {
                skipScaffoldButton
            }
        case .confirm:
            EmptyView()
        }
    }

    private var primaryCTAButton: some View {
        Button {
            withAnimation(stepTransitionAnimation) { viewModel.advance() }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .fill(viewModel.canAdvance ? AmenTheme.Colors.amenGold : AmenTheme.Colors.amenGold.opacity(0.40))
                    .frame(height: 52)
                Text("Continue")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.black.opacity(viewModel.canAdvance ? 1.0 : 0.5))
            }
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canAdvance)
        .accessibilityLabel("Continue to next step")
        .accessibilityHint(viewModel.canAdvance ? "Proceeds to the next step." : "Complete required fields to continue.")
    }

    private var skipScaffoldButton: some View {
        Button {
            viewModel.scaffold = SpaceBereanScaffold(
                description: "",
                passageRefs: nil,
                cadenceSuggestion: nil,
                discussionPrompts: [],
                suggestedTitle: nil
            )
            withAnimation(stepTransitionAnimation) { viewModel.currentStep = .access }
        } label: {
            Text("Skip AI suggestions")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background {
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                        .fill(AmenTheme.Colors.surfaceChip)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Skip AI suggestions and continue")
    }

    // MARK: - Computed

    private var currentStepIndex: Int {
        switch viewModel.currentStep {
        case .intent:   return 0
        case .scaffold: return 1
        case .access:   return 2
        case .confirm:  return 3
        }
    }

    private var stepTitle: String {
        switch viewModel.currentStep {
        case .intent:   return "Start something"
        case .scaffold: return "Review suggestions"
        case .access:   return "Access & pricing"
        case .confirm:  return "Confirm"
        }
    }

    private var stepTransitionAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.82)
    }

    private var stepTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
    }
}

#if DEBUG
#Preview("SpaceCreationWizard") {
    Text("Preview")
        .sheet(isPresented: .constant(true)) {
            SpaceCreationWizard(communityId: "preview_community")
        }
}
#endif
