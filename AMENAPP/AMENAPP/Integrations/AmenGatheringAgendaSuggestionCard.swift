// AmenGatheringAgendaSuggestionCard.swift
// Reusable selectable card for AI suggestions (titles, scripture, agenda items)

import SwiftUI

struct AmenGatheringAgendaSuggestionCard: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if let sub = subtitle, !sub.isEmpty {
                        Text(sub)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? .blue : Color(.tertiaryLabel))
                    .accessibilityHidden(true)
            }
            .padding(12)
            .background(
                isSelected ? Color.blue.opacity(0.07) : Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.blue.opacity(0.25) : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)\(subtitle.map { " — \($0)" } ?? ""). \(isSelected ? "Selected" : "Not selected"). Tap to select.")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    VStack(spacing: 12) {
        AmenGatheringAgendaSuggestionCard(
            title: "Evening of Prayer",
            subtitle: "Classic and welcoming",
            isSelected: true,
            onTap: {}
        )
        AmenGatheringAgendaSuggestionCard(
            title: "Seeking His Face",
            subtitle: "Scripture-focused (Psalm 27:8)",
            isSelected: false,
            onTap: {}
        )
    }
    .padding()
}
