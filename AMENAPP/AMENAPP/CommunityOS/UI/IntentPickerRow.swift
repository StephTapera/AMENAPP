// IntentPickerRow.swift
// AMEN App — Community OS
//
// Reusable horizontal scroll row of intent chips used inside AmenUniversalComposer.
// Intent raw values follow the C2 taxonomy (c2-intent-taxonomy.md).
//
// Design rules (C3-design-tokens.md):
//   • System semantic colors only — no amenGold, no hex
//   • Selected chip: white background, accentColor border + icon/text
//   • Unselected chip: secondarySystemFill background, secondaryLabel text
//   • Minimum 44pt touch target height

import SwiftUI

// MARK: - Intent metadata

/// Maps a C2 intent raw value to its display properties.
private struct IntentMeta {
    let rawValue: String
    let displayName: String
    let systemImage: String

    static let all: [IntentMeta] = [
        IntentMeta(rawValue: "share",     displayName: "Share",     systemImage: "square.and.arrow.up"),
        IntentMeta(rawValue: "discuss",   displayName: "Discuss",   systemImage: "bubble.left.and.bubble.right"),
        IntentMeta(rawValue: "pray",      displayName: "Pray",      systemImage: "hands.and.sparkles"),
        IntentMeta(rawValue: "study",     displayName: "Study",     systemImage: "book.pages"),
        IntentMeta(rawValue: "teach",     displayName: "Teach",     systemImage: "person.wave.2"),
        IntentMeta(rawValue: "ask",       displayName: "Ask",       systemImage: "questionmark.bubble"),
        IntentMeta(rawValue: "invite",    displayName: "Invite",    systemImage: "person.badge.plus"),
        IntentMeta(rawValue: "volunteer", displayName: "Volunteer", systemImage: "heart.circle"),
        IntentMeta(rawValue: "hire",      displayName: "Hire",      systemImage: "briefcase"),
        IntentMeta(rawValue: "mentor",    displayName: "Mentor",    systemImage: "person.2.circle"),
        IntentMeta(rawValue: "announce",  displayName: "Announce",  systemImage: "megaphone")
    ]

    static func meta(for rawValue: String) -> IntentMeta? {
        all.first { $0.rawValue == rawValue }
    }
}

// MARK: - IntentChip

/// A single selectable chip representing one C2 intent.
struct IntentChip: View {
    let intent: String      // AmenIntent raw value
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var meta: IntentMeta? { IntentMeta.meta(for: intent) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let meta {
                    Image(systemName: meta.systemImage)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    Text(meta.displayName)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                } else {
                    Text(intent)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                }
            }
            .foregroundStyle(
                isSelected
                    ? Color.accentColor
                    : Color(uiColor: .secondaryLabel)
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(chipBackground)
            .clipShape(Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor : Color.clear,
                        lineWidth: 1
                    )
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.12)
                    : .spring(response: 0.22, dampingFraction: 0.80),
                value: isSelected
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(meta?.displayName ?? intent)
        .accessibilityHint(isSelected ? "Selected" : "Tap to select \(meta?.displayName ?? intent)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var chipBackground: some View {
        if isSelected {
            Color.accentColor.opacity(0.08)
        } else {
            Color(uiColor: .secondarySystemFill)
        }
    }
}

// MARK: - IntentPickerRow

/// A horizontally scrolling row of `IntentChip` views.
/// Filters the full 11-intent set down to `availableIntents`.
struct IntentPickerRow: View {
    let availableIntents: [String]    // AmenIntent raw values to display
    @Binding var selectedIntent: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableIntents, id: \.self) { intentRaw in
                    IntentChip(
                        intent: intentRaw,
                        isSelected: selectedIntent == intentRaw
                    ) {
                        selectedIntent = (selectedIntent == intentRaw) ? nil : intentRaw
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Intent picker")
        .accessibilityHint("Choose what you want to create")
    }
}

// MARK: - Preview

#Preview("Intent Picker Row") {
    struct PreviewWrapper: View {
        @State private var selected: String? = "discuss"
        var body: some View {
            VStack(spacing: 20) {
                IntentPickerRow(
                    availableIntents: ["share", "discuss", "pray", "study", "teach", "ask"],
                    selectedIntent: $selected
                )

                IntentPickerRow(
                    availableIntents: ["invite", "volunteer", "hire", "mentor", "announce"],
                    selectedIntent: $selected
                )

                Text("Selected: \(selected ?? "none")")
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
            .padding(.vertical, 16)
            .background(Color(uiColor: .systemGroupedBackground))
        }
    }
    return PreviewWrapper()
}
