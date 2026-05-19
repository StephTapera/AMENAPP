import SwiftUI

struct LiquidGlassEntryStackView: View {
    let title: String
    let entries: [LivingEntry]
    var triggerReason: (LivingEntry) -> String? = { _ in nil }
    var stackDepth: CGFloat = 0
    var onComplete: (LivingEntry) -> Void
    var onTap: (LivingEntry) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                ForEach(entries) { entry in
                    LiquidGlassEntryCard(
                        entry: entry,
                        triggerReason: triggerReason(entry),
                        scrollDepth: stackDepth,
                        onComplete: { onComplete(entry) },
                        onTap: { onTap(entry) }
                    )
                }
            }
        }
    }
}
