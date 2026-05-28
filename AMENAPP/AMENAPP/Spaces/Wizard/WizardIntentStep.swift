// WizardIntentStep.swift
// AMENAPP — Spaces v2 Creation Wizard (Agent D)
//
// Step 1: Intent — "What are you starting?"
// Three glass type cards (Discussion / Study / Group) + title field + Continue button.
// Spring stagger animation on card appear (0.0, 0.1, 0.2s delays).
// amenGold border ring on selected card.

import SwiftUI

// MARK: - WizardIntentStep

struct WizardIntentStep: View {

    @ObservedObject var viewModel: SpaceCreationViewModel
    @FocusState private var titleFocused: Bool
    @State private var cardAppeared: [Bool] = [false, false, false]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: - Type options (no announcement)

    private var options: [IntentTypeOption] {
        [
            IntentTypeOption(spaceType: .chat,       label: "Discussion",  subtitle: "Open conversation",  symbol: "bubble.left.and.bubble.right"),
            IntentTypeOption(spaceType: .bibleStudy, label: "Study",       subtitle: "Guided Scripture",   symbol: "book.closed"),
            IntentTypeOption(spaceType: .group,      label: "Group",       subtitle: "Shared community",   symbol: "person.3")
        ]
    }

    var body: some View {
        VStack(spacing: 28) {
            headerLabel
            typeCards
            titleField
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .onAppear {
            titleFocused = true
            scheduleCardAppear()
        }
    }

    // MARK: - Header

    private var headerLabel: some View {
        VStack(spacing: 6) {
            Text("What are you starting?")
                .font(.title2.weight(.bold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text("Choose a type and give it a name.")
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Type cards

    private var typeCards: some View {
        HStack(spacing: 12) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                IntentTypeCard(
                    option: option,
                    isSelected: viewModel.selectedType == option.spaceType,
                    reduceTransparency: reduceTransparency,
                    reduceMotion: reduceMotion
                ) {
                    withAnimation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.7)) {
                        viewModel.selectedType = option.spaceType
                    }
                }
                .opacity(cardAppeared[index] ? 1 : 0)
                .offset(y: cardAppeared[index] ? 0 : 16)
                .accessibilityLabel("\(option.label): \(option.subtitle)")
                .accessibilityAddTraits(viewModel.selectedType == option.spaceType ? .isSelected : [])
                .accessibilityHint("Double-tap to select this Space type.")
            }
        }
    }

    // MARK: - Title field

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Give it a name...", text: $viewModel.title)
                .font(.body)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .focused($titleFocused)
                .submitLabel(.done)
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
                        .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.5)
                }
                .accessibilityLabel("Space name")
                .accessibilityHint("Enter a name for your new Space. Minimum 3 characters.")

            if viewModel.title.count > 0 && viewModel.title.count < 3 {
                Text("At least 3 characters required")
                    .font(.caption)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .padding(.leading, 4)
            }
        }
    }

    // MARK: - Stagger animation

    private func scheduleCardAppear() {
        for index in options.indices {
            let delay = Double(index) * 0.1
            if reduceMotion {
                cardAppeared[index] = true
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        cardAppeared[index] = true
                    }
                }
            }
        }
    }
}

// MARK: - IntentTypeOption

struct IntentTypeOption: Identifiable {
    let id = UUID()
    let spaceType: AmenSpace.SpaceType
    let label: String
    let subtitle: String
    let symbol: String
}

// MARK: - IntentTypeCard

private struct IntentTypeCard: View {

    let option: IntentTypeOption
    let isSelected: Bool
    let reduceTransparency: Bool
    let reduceMotion: Bool
    let onTap: () -> Void

    @State private var isPressed: Bool = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                Image(systemName: option.symbol)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(isSelected ? AmenTheme.Colors.amenGold : AmenTheme.Colors.textSecondary)
                    .frame(height: 36)

                Text(option.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? AmenTheme.Colors.textPrimary : AmenTheme.Colors.textSecondary)

                Text(option.subtitle)
                    .font(.caption)
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .padding(.horizontal, 8)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                        .fill(isSelected ? AmenTheme.Colors.selectedFill : AmenTheme.Colors.surfaceCard)
                } else {
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                                .fill(AmenTheme.Colors.glassFill.opacity(isSelected ? 0.5 : 1.0))
                        }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .strokeBorder(
                        isSelected ? AmenTheme.Colors.amenGold : AmenTheme.Colors.glassStroke,
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            }
            .shadow(
                color: isSelected ? AmenTheme.Colors.amenGold.opacity(0.20) : AmenTheme.Colors.shadowCard,
                radius: isSelected ? 12 : 8, x: 0, y: isSelected ? 4 : 2
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(reduceMotion ? .none : .spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
            .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.75), value: isSelected)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

#if DEBUG
#Preview("WizardIntentStep") {
    WizardIntentStep(viewModel: SpaceCreationViewModel())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
}
#endif
