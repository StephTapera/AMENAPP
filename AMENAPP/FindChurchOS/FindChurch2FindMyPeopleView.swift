// FindChurch2FindMyPeopleView.swift
// AMENAPP — Find Church 2.0, Wave 3
//
// Horizontal scrollable life-stage chip picker. Appears above search results
// when the findChurch2_gatherings flag is enabled.
//
// Usage:
//   FindChurch2FindMyPeoplePicker(selectedLifeStage: $selectedLifeStage)
//
// Design rules:
//   - Glass: .ultraThinMaterial for chip backgrounds — no custom Color + opacity stack
//   - No glass-on-glass nesting
//   - Luminous border: Color.white.opacity(0.45) at 0.5pt
//   - Shadow: radius 4, y 2, opacity 0.10
//   - Interactive targets ≥ 44×44pt
//   - @Environment(\.accessibilityReduceMotion) guards all animations
//   - Dynamic Type: .font(.system(.<style>)) — no fixed sizes

import SwiftUI
import Foundation

// MARK: - Life-stage presentation order & subset

private let pickerLifeStageTags: [GatheringObject.LifeStageTag] = [
    .youngAdults,
    .families,
    .singles,
    .college,
    .recovery,
    .newBelievers,
    .creatives
]

// MARK: - SF Symbol map

private extension GatheringObject.LifeStageTag {
    var systemImage: String {
        switch self {
        case .youngAdults:  return "person.2.fill"
        case .families:     return "house.fill"
        case .singles:      return "person.fill"
        case .college:      return "graduationcap.fill"
        case .recovery:     return "heart.circle.fill"
        case .newBelievers: return "book.fill"
        case .creatives:    return "paintbrush.fill"
        case .seniors:      return "figure.walk"
        case .teens:        return "backpack.fill"
        }
    }
}

// MARK: - FindChurch2FindMyPeoplePicker

/// Horizontal scrollable chip row for life-stage filtering.
/// Shows a curated subset: youngAdults, families, singles, college, recovery, newBelievers, creatives.
/// Selecting a chip sets the binding; tapping the same chip deselects (clears) it.
struct FindChurch2FindMyPeoplePicker: View {
    @Binding var selectedLifeStage: GatheringObject.LifeStageTag?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pickerLifeStageTags, id: \.rawValue) { tag in
                    LifeStageChip(
                        tag: tag,
                        isSelected: selectedLifeStage == tag,
                        reduceTransparency: reduceTransparency,
                        reduceMotion: reduceMotion
                    ) {
                        // Toggle: tap selected = deselect
                        if selectedLifeStage == tag {
                            selectedLifeStage = nil
                        } else {
                            selectedLifeStage = tag
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .accessibilityLabel("Filter by life stage")
        .accessibilityHint("Scroll horizontally to see all options")
    }
}

// MARK: - LifeStageChip (private)

private struct LifeStageChip: View {
    let tag: GatheringObject.LifeStageTag
    let isSelected: Bool
    let reduceTransparency: Bool
    let reduceMotion: Bool
    let action: () -> Void

    @GestureState private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tag.systemImage)
                    .font(.system(.caption).weight(.medium))
                    .foregroundStyle(isSelected ? .black : .primary)
                    .accessibilityHidden(true)
                Text(tag.displayName)
                    .font(.system(.subheadline).weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .black : .primary)
            }
            .padding(.horizontal, 14)
            .frame(minWidth: 44, minHeight: 44)
            .background(chipBackground)
            .overlay(chipBorder)
            .clipShape(Capsule(style: .continuous))
            .shadow(color: .black.opacity(isSelected ? 0.10 : 0.06), radius: 4, x: 0, y: 2)
            .scaleEffect(reduceMotion ? 1 : (isPressed ? 0.96 : 1))
        }
        .buttonStyle(.plain)
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, state, _ in state = true }
        )
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.12)
                : .spring(response: 0.22, dampingFraction: 0.80),
            value: isPressed
        )
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.12)
                : .spring(response: 0.28, dampingFraction: 0.76),
            value: isSelected
        )
        .accessibilityLabel(tag.displayName)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(isSelected ? "Tap to remove this filter" : "Tap to filter by \(tag.displayName)")
    }

    @ViewBuilder
    private var chipBackground: some View {
        if isSelected {
            // Gold gradient fill for selected state — not glass (avoids glass-on-glass)
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.82, blue: 0.28),
                            Color(red: 1.0, green: 0.60, blue: 0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        } else if reduceTransparency {
            Capsule(style: .continuous)
                .fill(Color(.secondarySystemBackground))
        } else {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }

    private var chipBorder: some View {
        Capsule(style: .continuous)
            .strokeBorder(
                isSelected
                    ? Color.white.opacity(0.55)
                    : Color.white.opacity(0.45),
                lineWidth: 0.5
            )
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Find My People Picker") {
    StatefulPreviewWrapper(nil as GatheringObject.LifeStageTag?) { binding in
        VStack(spacing: 16) {
            FindChurch2FindMyPeoplePicker(selectedLifeStage: binding)

            if let selected = binding.wrappedValue {
                Text("Selected: \(selected.displayName)")
                    .font(.system(.caption))
                    .foregroundStyle(.secondary)
            } else {
                Text("No filter selected")
                    .font(.system(.caption))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical)
    }
}

// Minimal stateful preview wrapper to keep preview self-contained
private struct StatefulPreviewWrapper<T, Content: View>: View {
    @State private var value: T
    private let content: (Binding<T>) -> Content

    init(_ initialValue: T, @ViewBuilder content: @escaping (Binding<T>) -> Content) {
        self._value = State(initialValue: initialValue)
        self.content = content
    }

    var body: some View {
        content($value)
    }
}
#endif
