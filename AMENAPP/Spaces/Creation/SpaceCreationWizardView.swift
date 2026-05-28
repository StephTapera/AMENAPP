// SpaceCreationWizardView.swift
// AMENAPP — Spaces v2 Creation Wizard (Agent D)
//
// Top-level wizard container. Hosts all 4 steps with animated step indicator
// and spring transitions. Presented full-screen as a sheet by the parent.
//
// Entry point:
//   SpaceCreationWizardView(communityId:creatorUserId:isPresented:onCreated:)

import SwiftUI

// MARK: - SpaceCreationWizardView

struct SpaceCreationWizardView: View {

    let communityId: String
    let creatorUserId: String
    @Binding var isPresented: Bool
    /// Called with the new spaceId when creation completes.
    var onCreated: ((String) -> Void)? = nil

    @StateObject private var vm = SpacesCreationViewModel()
    @State private var showCancelConfirmation = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            // Glass background
            Rectangle()
                .fill(LiquidGlassTokens.blurThin)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Navigation chrome
                wizardNavBar

                // Step indicator
                StepIndicatorRow(
                    totalSteps: SpacesCreationViewModel.CreationStep.allCases.count,
                    currentStep: vm.currentStep.rawValue
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 8)

                // Step body
                stepBody
                    .transition(
                        reduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        )
                    )
            }
        }
        .onChange(of: vm.isComplete) { _, complete in
            if complete, let spaceId = vm.draft.createdSpaceId {
                onCreated?(spaceId)
                isPresented = false
            }
        }
        .confirmationDialog(
            "Discard this Space?",
            isPresented: $showCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { isPresented = false }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("Your progress will be lost.")
        }
    }

    // MARK: - Navigation bar

    @ViewBuilder
    private var wizardNavBar: some View {
        HStack {
            // Back button (hidden on step 0)
            if vm.currentStep.rawValue > 0 {
                Button {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.18) : Motion.liquidSpring) {
                        vm.goBack()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.medium))
                        .foregroundStyle(AmenTheme.Colors.amenGold)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Back")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }

            Spacer()

            Text(vm.currentStep.title)
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer()

            // Cancel button
            Button {
                if vm.draft.title.isEmpty {
                    isPresented = false
                } else {
                    showCancelConfirmation = true
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Cancel")
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    // MARK: - Step body router

    @ViewBuilder
    private var stepBody: some View {
        switch vm.currentStep {
        case .intent:
            WizardStepIntentView(vm: vm)
                .id(SpacesCreationViewModel.CreationStep.intent)

        case .scaffold:
            WizardStepScaffoldView(vm: vm)
                .id(SpacesCreationViewModel.CreationStep.scaffold)

        case .pricing:
            WizardStepPricingView(vm: vm)
                .id(SpacesCreationViewModel.CreationStep.pricing)

        case .confirm:
            WizardStepConfirmView(
                vm: vm,
                communityId: communityId,
                creatorUserId: creatorUserId
            )
            .id(SpacesCreationViewModel.CreationStep.confirm)
        }
    }
}

// MARK: - Step title helper

private extension SpacesCreationViewModel.CreationStep {
    var title: String {
        switch self {
        case .intent:   return "New Space"
        case .scaffold: return "Berean Suggests"
        case .pricing:  return "Access & Pricing"
        case .confirm:  return "Ready to create"
        }
    }
}

// MARK: - StepIndicatorRow

struct StepIndicatorRow: View {
    let totalSteps: Int
    let currentStep: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index <= currentStep
                          ? AmenTheme.Colors.amenGold
                          : AmenTheme.Colors.amenSilver.opacity(0.35))
                    .frame(width: index == currentStep ? 24 : 8, height: 6)
                    .animation(
                        reduceMotion ? .easeOut(duration: 0.12) : Motion.liquidSpring,
                        value: currentStep
                    )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(currentStep + 1) of \(totalSteps)")
        .accessibilityValue(stepLabel(currentStep))
    }

    private func stepLabel(_ step: Int) -> String {
        switch step {
        case 0: return "Intent"
        case 1: return "Scaffold"
        case 2: return "Pricing"
        case 3: return "Confirm"
        default: return ""
        }
    }
}

// MARK: - SpaceWizardGlassCard modifier
// Named distinctly to avoid collision with ChurchNotesDesignSystem's GlassCardModifier.

struct SpaceWizardGlassCard: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                        .fill(Color(.systemBackground))
                } else {
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                        .fill(LiquidGlassTokens.blurThin)
                        .overlay {
                            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                                .fill(Color.white.opacity(0.12))
                        }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .stroke(Color.white.opacity(0.28), lineWidth: 0.5)
            }
            .shadow(
                color: LiquidGlassTokens.shadowSoft.color,
                radius: LiquidGlassTokens.shadowSoft.radius,
                y: LiquidGlassTokens.shadowSoft.y
            )
    }
}

extension View {
    func wizardGlassCard() -> some View {
        modifier(SpaceWizardGlassCard())
    }
}
