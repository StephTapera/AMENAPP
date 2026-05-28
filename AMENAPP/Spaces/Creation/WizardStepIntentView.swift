// WizardStepIntentView.swift
// AMENAPP — Spaces v2 Creation Wizard, Step 1 (Agent D)
//
// Name your Space + choose an intent (Discussion / Study / Group).
// "Next" is enabled only when title is non-empty AND an intent is selected.

import SwiftUI

struct WizardStepIntentView: View {

    @ObservedObject var vm: SpacesCreationViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                titleField
                descriptionField
                intentCards
                Spacer(minLength: 20)
                nextButton
            }
            .padding(20)
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.12) : Motion.liquidSpring,
            value: vm.draft.intent
        )
    }

    // MARK: - Title field

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Space name")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            TextField("Name your Space", text: $vm.draft.title)
                .font(.body)
                .submitLabel(.next)
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
                .accessibilityLabel("Space name")
        }
    }

    // MARK: - Description field

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Description")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(vm.draft.description.count)/200")
                    .font(.caption)
                    .foregroundStyle(
                        vm.draft.description.count > 200
                        ? AmenTheme.Colors.amenBronze
                        : Color(uiColor: .tertiaryLabel)
                    )
            }

            TextField("Optional \u{2014} describe what this Space is for", text: $vm.draft.description, axis: .vertical)
                .font(.body)
                .lineLimit(3...5)
                .onChange(of: vm.draft.description) { _, newVal in
                    if newVal.count > 200 {
                        vm.draft.description = String(newVal.prefix(200))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background {
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                        .fill(LiquidGlassTokens.blurThin)
                        .overlay {
                            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                                .fill(Color.white.opacity(0.12))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                                .stroke(Color.white.opacity(0.28), lineWidth: 0.5)
                        }
                }
                .accessibilityLabel("Description")
        }
    }

    // MARK: - Intent cards

    private var intentCards: some View {
        VStack(spacing: 12) {
            Text("What kind of Space?")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(SpaceCreationIntent.allCases) { creationIntent in
                SpaceWizardIntentCard(
                    intent: creationIntent,
                    isSelected: vm.draft.intent == creationIntent
                ) {
                    vm.draft.intent = creationIntent
                }
            }
        }
    }

    // MARK: - Next button

    private var nextButton: some View {
        AmenLiquidGlassPillButton(
            title: "Next",
            systemImage: "arrow.right",
            isLoading: false,
            isDisabled: !vm.draft.canAdvanceFromIntent
        ) {
            if let creationIntent = vm.draft.intent {
                withAnimation(reduceMotion ? .easeOut(duration: 0.18) : Motion.liquidSpring) {
                    vm.selectIntent(creationIntent)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHint("Advances to Berean scaffold step")
    }
}

// MARK: - SpaceWizardIntentCard
// Named distinctly to avoid collision with AmenSyncEntryView's IntentCard.

private struct SpaceWizardIntentCard: View {
    let intent: SpaceCreationIntent
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isSelected
                              ? AmenTheme.Colors.amenGold.opacity(0.18)
                              : Color.white.opacity(0.06))
                        .frame(width: 44, height: 44)
                    Image(systemName: intent.systemImageName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(isSelected
                                         ? AmenTheme.Colors.amenGold
                                         : Color.secondary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(intent.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                    Text(intent.description)
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(2)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AmenTheme.Colors.amenGold)
                        .font(.body.weight(.semibold))
                }
            }
            .padding(14)
            .wizardGlassCard()
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                        .stroke(AmenTheme.Colors.amenGold.opacity(0.55), lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
        .animation(
            reduceMotion ? .easeOut(duration: 0.12) : Motion.liquidSpring,
            value: isSelected
        )
        .accessibilityLabel("\(intent.displayName): \(intent.description)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint("Double-tap to select \(intent.displayName)")
    }
}
