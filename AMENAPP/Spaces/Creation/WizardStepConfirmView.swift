// WizardStepConfirmView.swift
// AMENAPP — Spaces v2 Creation Wizard, Step 4 (Agent D)
//
// Hero confirm screen. Shows a summary of choices, then triggers space creation.
// On success emits the new spaceId via the parent's onCreated closure.

import SwiftUI
import FirebaseAuth

struct WizardStepConfirmView: View {

    @ObservedObject var vm: SpacesCreationViewModel
    let communityId: String
    let creatorUserId: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var intent: SpaceCreationIntent? { vm.draft.intent }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                heroHeader
                summaryCards
                if let error = vm.creationError { errorBanner(error) }
                createButton
            }
            .padding(20)
        }
    }

    // MARK: - Hero header

    private var heroHeader: some View {
        VStack(spacing: 12) {
            // Type icon in amenGold circle (80 pt)
            ZStack {
                Circle()
                    .fill(AmenTheme.Colors.amenGold.opacity(0.15))
                    .frame(width: 80, height: 80)
                    .overlay {
                        Circle()
                            .stroke(AmenTheme.Colors.amenGold.opacity(0.35), lineWidth: 1.5)
                    }

                Image(systemName: intent?.systemImageName ?? "square.grid.2x2.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.amenGold)
            }
            .accessibilityHidden(true)

            // Space title
            Text(vm.draft.title.isEmpty ? "Your Space" : vm.draft.title)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(3)

            // Intent + creator row
            HStack(spacing: 8) {
                if let intent {
                    Label(intent.displayName, systemImage: intent.systemImageName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                if let displayName = Auth.auth().currentUser?.displayName, !displayName.isEmpty {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("by \(displayName)")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityHeroLabel)
    }

    private var accessibilityHeroLabel: String {
        let name = vm.draft.title.isEmpty ? "Unnamed Space" : vm.draft.title
        let type = intent?.displayName ?? "Space"
        return "\(name), \(type)"
    }

    // MARK: - Summary cards

    private var summaryCards: some View {
        VStack(spacing: 12) {

            // Scaffold summary
            SummaryCard(
                icon: "sparkles",
                label: "AI Scaffold",
                value: scaffoldSummary
            )

            // Access / pricing summary
            SummaryCard(
                icon: vm.draft.pricingState.policy == .free ? "lock.open.fill" : "lock.fill",
                label: "Access",
                value: accessSummary
            )

            // Description preview (if provided)
            if !vm.draft.description.isEmpty {
                SummaryCard(
                    icon: "text.alignleft",
                    label: "Description",
                    value: vm.draft.description
                )
            }
        }
    }

    private var scaffoldSummary: String {
        guard vm.draft.scaffoldAccepted, let scaffold = vm.draft.scaffold else {
            return "No AI scaffold"
        }
        if vm.draft.intent == .study {
            let weeks = scaffold.cadence ?? "scheduled study"
            let count = scaffold.blockDrafts.count
            return "AI-suggested \(weeks) · \(count) block\(count == 1 ? "" : "s")"
        } else {
            let count = scaffold.starterPrompts.count
            return "AI-suggested \(count) starter thread\(count == 1 ? "" : "s")"
        }
    }

    private var accessSummary: String {
        let pricing = vm.draft.pricingState
        switch pricing.policy {
        case .free:
            return "Free — open to all members"
        case .oneTime:
            let dollars = String(format: "$%.2f", Double(pricing.amountCents) / 100.0)
            let payout  = SpacesFeeCalculator.payoutLabel(amountCents: pricing.amountCents)
            return "\(dollars) one-time · \(payout)"
        case .recurring:
            let dollars = String(format: "$%.2f", Double(pricing.amountCents) / 100.0)
            let period  = pricing.interval == "year" ? "year" : "month"
            let payout  = SpacesFeeCalculator.payoutLabel(amountCents: pricing.amountCents)
            return "\(dollars)/\(period) · \(payout)"
        }
    }

    // MARK: - Error banner

    @ViewBuilder
    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(AmenTheme.Colors.amenBronze)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                .fill(AmenTheme.Colors.amenBronze.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                        .stroke(AmenTheme.Colors.amenBronze.opacity(0.28), lineWidth: 0.8)
                }
        }
        .accessibilityLabel("Error: \(message)")
    }

    // MARK: - Create button

    private var createButton: some View {
        AmenLiquidGlassPillButton(
            title: "Create Space",
            systemImage: "plus.circle.fill",
            isLoading: vm.isCreating,
            isDisabled: vm.isCreating,
            hint: "Creates your Space and sets up the scaffold"
        ) {
            Task {
                await vm.createSpace(communityId: communityId, creatorUserId: creatorUserId)
            }
        }
        .frame(maxWidth: .infinity)
        .tint(AmenTheme.Colors.amenGold)
    }
}

// MARK: - SummaryCard

private struct SummaryCard: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(AmenTheme.Colors.amenGold)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .wizardGlassCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }
}
