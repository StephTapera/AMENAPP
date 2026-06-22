import SwiftUI

struct LiquidGlassEntryCard: View {
    let entry: LivingEntry
    var triggerReason: String?
    var scrollDepth: CGFloat = 0
    var onComplete: (() -> Void)? = nil
    var onTap: (() -> Void)? = nil

    @State private var pressed = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            onTap?()
        } label: {
            LivingEntryLiquidGlassCard(
                contextTint: tint,
                elevated: entry.state == .needsReflection,
                pressed: pressed,
                scrollDepth: scrollDepth
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.title)
                                .font(.headline)
                                .foregroundStyle(primaryTextColor)
                            if !entry.previewBody.isEmpty {
                                Text(entry.previewBody)
                                    .font(.subheadline)
                                    .foregroundStyle(primaryTextColor.opacity(0.7))
                                    .lineLimit(3)
                            }
                        }
                        Spacer()
                        if let onComplete {
                            Button {
                                onComplete()
                            } label: {
                                Image(systemName: entry.state == .completed ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(primaryTextColor)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(entry.state == .completed ? "Completed" : "Complete entry")
                        }
                    }

                    HStack(spacing: 8) {
                        chip(text: entry.intent.rawValue)
                        if let triggerReason {
                            chip(text: triggerReason)
                        }
                    }

                    if let nextAction = entry.suggestedNextAction, !nextAction.isEmpty {
                        Text(nextAction)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(primaryTextColor.opacity(0.72))
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
        .scaleEffect(!reduceMotion && entry.state == .active && scrollDepth < 1 ? 1.002 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var tint: Color {
        switch entry.intent {
        case .churchVisit, .sermonReflection, .spiritualGrowth:
            return Color.orange
        case .prayerCare:
            return Color.blue
        case .relationship:
            return Color.green
        case .work:
            return Color.gray
        case .rest:
            return Color.yellow
        case .personal, .unknown:
            return Color.black.opacity(0.1)
        }
    }

    private func chip(text: String) -> some View {
        Text(text.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.caption.weight(.medium))
            .foregroundStyle(primaryTextColor.opacity(0.7))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.6)))
    }

    private var accessibilityLabel: String {
        [entry.title, triggerReason, entry.suggestedNextAction].compactMap { $0 }.joined(separator: ", ")
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }
}
