// WizardAccessStep.swift
// AMENAPP — Spaces v2 Creation Wizard (Agent D)
//
// Step 3: Access & pricing.
// Glass segmented control: Free | One-time | Recurring
// Spring selection animation.
// When paid: "$" + amount field, min $1.00.
// Recurring: Weekly / Monthly / Yearly interval chips.
// Live fee preview via SpacesFeeCalculatorE.

import SwiftUI

struct WizardAccessStep: View {

    @ObservedObject var viewModel: SpaceCreationViewModel

    @State private var amountString: String = ""
    @FocusState private var amountFocused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let policies: [(AmenSpace.AccessPolicy, String)] = [
        (.free,      "Free"),
        (.oneTime,   "One-time"),
        (.recurring, "Recurring")
    ]

    private let intervals: [(String, String)] = [
        ("weekly",  "Weekly"),
        ("monthly", "Monthly"),
        ("yearly",  "Yearly")
    ]

    var body: some View {
        VStack(spacing: 28) {
            headerLabel
            accessPolicyPicker

            if viewModel.accessPolicy != .free {
                amountSection
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }

            if !viewModel.feePreviewString.isEmpty {
                feePreviewLabel.transition(.opacity)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .animation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.8), value: viewModel.accessPolicy)
        .onAppear {
            if viewModel.amountCents > 0 {
                amountString = String(format: "%.2f", Double(viewModel.amountCents) / 100.0)
            }
        }
    }

    // MARK: - Header

    private var headerLabel: some View {
        VStack(spacing: 6) {
            Text("Access & pricing")
                .font(.title2.weight(.bold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text("Free Spaces are open to all members.")
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Policy picker

    @Namespace private var pickerNamespace

    private var accessPolicyPicker: some View {
        HStack(spacing: 0) {
            ForEach(policies, id: \.0) { policy, label in
                Button {
                    withAnimation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.75)) {
                        viewModel.accessPolicy = policy
                        if policy == .free {
                            viewModel.amountCents = 0
                            viewModel.selectedInterval = nil
                        } else if policy == .recurring && viewModel.selectedInterval == nil {
                            viewModel.selectedInterval = "monthly"
                        }
                    }
                } label: {
                    Text(label)
                        .font(.subheadline.weight(viewModel.accessPolicy == policy ? .semibold : .regular))
                        .foregroundStyle(
                            viewModel.accessPolicy == policy
                                ? AmenTheme.Colors.textPrimary
                                : AmenTheme.Colors.textSecondary
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background {
                            if viewModel.accessPolicy == policy {
                                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                                    .fill(AmenTheme.Colors.selectedFill)
                                    .matchedGeometryEffect(id: "AccessSelector", in: pickerNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
                .accessibilityAddTraits(viewModel.accessPolicy == policy ? .isSelected : [])
                .accessibilityHint("Double-tap to set access to \(label)")
            }
        }
        .padding(4)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .fill(AmenTheme.Colors.surfaceChip)
            } else {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                            .fill(AmenTheme.Colors.glassFill)
                    }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.5)
        }
    }

    // MARK: - Amount section

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 4) {
                Text("$")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)

                TextField("0.00", text: $amountString)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .keyboardType(.decimalPad)
                    .focused($amountFocused)
                    .onChange(of: amountString) { parseAmountCents(from: amountString) }
                    .accessibilityLabel("Price amount in dollars")

                Spacer()

                Text("USD")
                    .font(.subheadline)
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                        .fill(AmenTheme.Colors.surfaceInput)
                } else {
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                                .fill(AmenTheme.Colors.glassFill)
                        }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                    .strokeBorder(
                        viewModel.amountCents > 0 && viewModel.amountCents < 100
                            ? AmenTheme.Colors.statusError.opacity(0.6)
                            : AmenTheme.Colors.glassStroke,
                        lineWidth: 0.5
                    )
            }

            if viewModel.amountCents > 0 && viewModel.amountCents < 100 {
                Text("Minimum price is $1.00")
                    .font(.caption)
                    .foregroundStyle(AmenTheme.Colors.statusError)
                    .padding(.leading, 4)
            }

            if viewModel.accessPolicy == .recurring {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Billing interval")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)

                    HStack(spacing: 10) {
                        ForEach(intervals, id: \.0) { key, label in
                            Button {
                                withAnimation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.75)) {
                                    viewModel.selectedInterval = key
                                }
                            } label: {
                                Text(label)
                                    .font(.subheadline.weight(viewModel.selectedInterval == key ? .semibold : .regular))
                                    .foregroundStyle(
                                        viewModel.selectedInterval == key
                                            ? AmenTheme.Colors.textPrimary
                                            : AmenTheme.Colors.textSecondary
                                    )
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background {
                                        Capsule(style: .continuous)
                                            .fill(
                                                viewModel.selectedInterval == key
                                                    ? AmenTheme.Colors.amenGold.opacity(0.18)
                                                    : AmenTheme.Colors.surfaceChip
                                            )
                                    }
                                    .overlay {
                                        Capsule(style: .continuous)
                                            .strokeBorder(
                                                viewModel.selectedInterval == key
                                                    ? AmenTheme.Colors.amenGold
                                                    : AmenTheme.Colors.glassStroke,
                                                lineWidth: viewModel.selectedInterval == key ? 1.0 : 0.5
                                            )
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(label)
                            .accessibilityAddTraits(viewModel.selectedInterval == key ? .isSelected : [])
                            .animation(reduceMotion ? .none : .spring(response: 0.25), value: viewModel.selectedInterval)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Fee preview

    private var feePreviewLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 14))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .accessibilityHidden(true)
            Text(viewModel.feePreviewString)
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                .fill(AmenTheme.Colors.surfaceChip)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(viewModel.feePreviewString)
    }

    // MARK: - Parsing

    private func parseAmountCents(from raw: String) {
        let cleaned = raw.filter { $0.isNumber || $0 == "." }
        guard let value = Double(cleaned) else {
            viewModel.amountCents = 0
            return
        }
        viewModel.amountCents = Int((value * 100).rounded())
    }
}

#if DEBUG
#Preview("WizardAccessStep") {
    let vm = SpaceCreationViewModel()
    vm.accessPolicy = .recurring
    vm.selectedInterval = "monthly"
    vm.amountCents = 999
    return WizardAccessStep(viewModel: vm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
}
#endif
