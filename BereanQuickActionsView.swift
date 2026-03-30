//
//  BereanQuickActionsView.swift
//  AMENAPP
//
//  Horizontally scrollable chip row shown above the Berean input field
//  when no conversation is active. Each chip pre-fills the input with a
//  relevant prompt template for the selected quick-action.
//

import SwiftUI

// MARK: - BereanQuickActionChip Model

struct BereanQuickActionChip: Identifiable {
    let id = UUID()
    let emoji: String
    let label: String
    let prompt: String
    let cardType: BereanCardType  // used if the response should be rendered as a structured card
}

extension BereanQuickActionChip {
    static let all: [BereanQuickActionChip] = [
        BereanQuickActionChip(
            emoji: "📖",
            label: "Sermon Fact-Check",
            prompt: "Please fact-check this claim from a sermon using Scripture: ",
            cardType: .factCheck
        ),
        BereanQuickActionChip(
            emoji: "🙏",
            label: "Build a Prayer",
            prompt: "Build a heartfelt prayer for me about: ",
            cardType: .prayer
        ),
        BereanQuickActionChip(
            emoji: "⚖️",
            label: "Debate Mode",
            prompt: "Give me two biblical perspectives on this topic, showing both sides fairly: ",
            cardType: .debate
        ),
        BereanQuickActionChip(
            emoji: "🌍",
            label: "Big Decision",
            prompt: "I'm facing a big decision and need biblical wisdom to help me discern: ",
            cardType: .decision
        ),
        BereanQuickActionChip(
            emoji: "💰",
            label: "Budget Coach",
            prompt: "Give me biblical principles and practical tips for managing money and budgeting in this situation: ",
            cardType: .generic
        ),
        BereanQuickActionChip(
            emoji: "📰",
            label: "News Filter",
            prompt: "Help me think through this news or cultural event through a biblical lens: ",
            cardType: .generic
        ),
        BereanQuickActionChip(
            emoji: "✉️",
            label: "Draft Message",
            prompt: "Help me draft a kind, grace-filled message to send to someone about: ",
            cardType: .generic
        ),
        BereanQuickActionChip(
            emoji: "🍽️",
            label: "Meal & Fasting",
            prompt: "Give me a biblical perspective on fasting and a simple plan for: ",
            cardType: .meal
        ),
        BereanQuickActionChip(
            emoji: "👶",
            label: "Parenting Help",
            prompt: "Give me biblical guidance and practical advice for this parenting situation: ",
            cardType: .generic
        ),
        BereanQuickActionChip(
            emoji: "💡",
            label: "Stress Test Idea",
            prompt: "Help me evaluate this idea or plan using biblical wisdom and critical thinking: ",
            cardType: .generic
        ),
        BereanQuickActionChip(
            emoji: "🌙",
            label: "End My Day",
            prompt: "Help me reflect on my day with gratitude and close it in prayer. Today I experienced: ",
            cardType: .prayer
        ),
        BereanQuickActionChip(
            emoji: "🎯",
            label: "My Goals",
            prompt: "Help me set a faith-centered goal and create a biblical action plan for: ",
            cardType: .generic
        ),
    ]
}

// MARK: - BereanQuickActionsView

/// Horizontally scrollable chip row. Place above the Berean input bar
/// when no conversation is active. `selectedPrompt` is set on chip tap so
/// the parent can pre-fill its input field.
struct BereanQuickActionsView: View {

    /// Binding to the parent's input text — chip tap writes the prompt template here.
    @Binding var inputText: String
    /// Optional: exposes the selected chip's card type so parent can configure structured output.
    @Binding var selectedCardType: BereanCardType

    var onChipSelected: ((BereanQuickActionChip) -> Void)? = nil

    @State private var selectedChipId: UUID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section label
            Text("Quick actions")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(white: 0.55))
                .kerning(0.6)
                .textCase(.uppercase)
                .padding(.horizontal, 20)

            // Horizontally scrollable chip row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BereanQuickActionChip.all) { chip in
                        chipButton(chip)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Chip Button

    @ViewBuilder
    private func chipButton(_ chip: BereanQuickActionChip) -> some View {
        let isSelected = selectedChipId == chip.id

        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                selectedChipId = chip.id
            }
            // Pre-fill input with the chip's prompt template
            inputText = chip.prompt
            selectedCardType = chip.cardType
            onChipSelected?(chip)
        } label: {
            HStack(spacing: 5) {
                Text(chip.emoji)
                    .font(.system(size: 13))
                Text(chip.label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .white : Color(white: 0.28))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(
                        isSelected
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.88, green: 0.38, blue: 0.28),
                                        Color(red: 0.72, green: 0.28, blue: 0.45)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                              )
                            : AnyShapeStyle(Color.white)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                isSelected
                                    ? Color.clear
                                    : Color.black.opacity(0.09),
                                lineWidth: 0.8
                            )
                    )
                    .shadow(
                        color: isSelected
                            ? Color(red: 0.88, green: 0.38, blue: 0.28).opacity(0.28)
                            : Color.black.opacity(0.04),
                        radius: isSelected ? 6 : 3,
                        y: isSelected ? 3 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.04 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isSelected)
        .accessibilityLabel("\(chip.emoji) \(chip.label)")
        .accessibilityHint("Pre-fills input with a \(chip.label) prompt")
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Quick Actions Row") {
    @Previewable @State var input = ""
    @Previewable @State var cardType: BereanCardType = .generic

    VStack {
        BereanQuickActionsView(inputText: $input, selectedCardType: $cardType)
            .padding(.vertical, 12)
            .background(Color(red: 0.97, green: 0.97, blue: 0.97))

        if !input.isEmpty {
            Text("Input: \(input)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
    }
}
#endif
