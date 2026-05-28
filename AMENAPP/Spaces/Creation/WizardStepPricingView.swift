// WizardStepPricingView.swift
// AMENAPP — Spaces v2 Creation Wizard, Step 3 (Agent D)
//
// Access & pricing: Free / One-time / Monthly / Yearly segmented glass control
// with live payout label from SpacesFeeCalculator (Agent E, read-only).

import SwiftUI

struct WizardStepPricingView: View {

    @ObservedObject var vm: SpacesCreationViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Local editing state — flushed to vm on "Next"
    @State private var localState: SpacesPricingState

    init(vm: SpacesCreationViewModel) {
        self.vm = vm
        self._localState = State(initialValue: vm.draft.pricingState)
    }

    private var isPaid: Bool { localState.policy != .free }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                policyPicker
                if isPaid { priceEntry }
                Spacer(minLength: 20)
                nextButton
            }
            .padding(20)
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.12) : Motion.liquidSpring,
            value: isPaid
        )
    }

    // MARK: - Policy picker

    private var policyPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Who can join?")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                policyPill(label: "Free",     policy: .free,      interval: nil)
                policyPill(label: "One-time", policy: .oneTime,   interval: nil)
                policyPill(label: "Monthly",  policy: .recurring, interval: "month")
                policyPill(label: "Yearly",   policy: .recurring, interval: "year")
            }
            .padding(4)
            .background {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .fill(LiquidGlassTokens.blurThin)
                    .overlay {
                        RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                            .stroke(Color.white.opacity(0.24), lineWidth: 0.5)
                    }
            }
        }
    }

    @ViewBuilder
    private func policyPill(label: String, policy: AccessPolicy, interval: String?) -> some View {
        let isSelected = localState.policy == policy
                      && (policy == .free || localState.interval == interval)

        Button {
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : Motion.liquidSpring) {
                localState.policy   = policy
                localState.interval = interval
            }
        } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? .black : .primary)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                            .fill(AmenTheme.Colors.amenGold)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel(label)
    }

    // MARK: - Price entry

    private var priceEntry: some View {
        VStack(spacing: 14) {
            // Amount field
            VStack(alignment: .leading, spacing: 6) {
                Text("Price")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Text("$")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)

                    TextField("0.00", text: amountBinding)
                        .font(.title3.weight(.semibold))
                        .keyboardType(.decimalPad)
                        .accessibilityLabel("Price in dollars")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background {
                    Capsule(style: .continuous)
                        .fill(LiquidGlassTokens.blurThin)
                        .overlay {
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.12))
                        }
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.28), lineWidth: 0.5)
                        }
                }
            }

            // Interval descriptor
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
                Text(intervalDescriptor)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            // Payout label from SpacesFeeCalculator
            HStack {
                Image(systemName: "arrow.up.forward.circle")
                    .foregroundStyle(AmenTheme.Colors.amenGold)
                Text(SpacesFeeCalculator.payoutLabel(amountCents: localState.amountCents))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AmenTheme.Colors.amenGold)
                Spacer()
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .fill(AmenTheme.Colors.amenGold.opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                            .stroke(AmenTheme.Colors.amenGold.opacity(0.2), lineWidth: 0.8)
                    }
            }
            .accessibilityLabel(SpacesFeeCalculator.payoutLabel(amountCents: localState.amountCents))

            // Minimum price warning
            if localState.amountCents < 50 && localState.amountCents > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(AmenTheme.Colors.amenBronze)
                    Text("Minimum price is $0.50")
                        .font(.caption)
                        .foregroundStyle(AmenTheme.Colors.amenBronze)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .wizardGlassCard()
    }

    // MARK: - Amount binding

    private var amountBinding: Binding<String> {
        Binding(
            get: {
                localState.amountCents == 0
                ? ""
                : String(format: "%.2f", Double(localState.amountCents) / 100.0)
            },
            set: { newValue in
                let stripped = newValue.replacingOccurrences(of: "$", with: "")
                if let dollars = Double(stripped) {
                    localState.amountCents = max(0, Int((dollars * 100).rounded()))
                } else if stripped.isEmpty {
                    localState.amountCents = 0
                }
            }
        )
    }

    private var intervalDescriptor: String {
        switch (localState.policy, localState.interval) {
        case (.free, _):             return "Free — open to all members"
        case (.oneTime, _):          return "One-time payment"
        case (.recurring, "month"):  return "Billed monthly"
        case (.recurring, "year"):   return "Billed yearly"
        default:                     return "One-time payment"
        }
    }

    // MARK: - Next button

    private var nextButton: some View {
        AmenLiquidGlassPillButton(
            title: "Next",
            systemImage: "arrow.right",
            isLoading: false,
            isDisabled: !localState.isValid
        ) {
            vm.setPricing(localState)
            withAnimation(reduceMotion ? .easeOut(duration: 0.18) : Motion.liquidSpring) {
                vm.currentStep = .confirm
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHint("Advances to confirmation step")
    }
}
