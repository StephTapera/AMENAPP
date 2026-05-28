import SwiftUI

struct MoodTagPicker: View {
    @Binding var selectedTags: Set<MoodTag>
    var onChange: (Set<MoodTag>) -> Void

    @State private var selectionOrder: [MoodTag] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MoodTag.allCases) { tag in
                    moodPill(tag)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private func moodPill(_ tag: MoodTag) -> some View {
        let isSelected = selectedTags.contains(tag)
        return Button {
            toggle(tag)
        } label: {
            HStack(spacing: 4) {
                Text(tag.emoji).font(.system(size: 13))
                Text(tag.label).font(.caption.weight(.medium))
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(height: 28)
            .background {
                Capsule()
                    .fill(isSelected
                        ? AnyShapeStyle(tag.tintColor)
                        : (reduceTransparency ? AnyShapeStyle(Color(.systemFill)) : AnyShapeStyle(LiquidGlassTokens.blurThin)))
                    .overlay(Capsule().strokeBorder(
                        isSelected ? Color.white.opacity(0.28) : Color.white.opacity(0.22),
                        lineWidth: 0.6
                    ))
            }
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.70), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tag.label) \(isSelected ? "selected" : "")")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func toggle(_ tag: MoodTag) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
            selectionOrder.removeAll { $0 == tag }
        } else {
            if selectedTags.count >= 2, let oldest = selectionOrder.first {
                selectedTags.remove(oldest)
                selectionOrder.removeFirst()
            }
            selectedTags.insert(tag)
            selectionOrder.append(tag)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onChange(selectedTags)
    }
}
