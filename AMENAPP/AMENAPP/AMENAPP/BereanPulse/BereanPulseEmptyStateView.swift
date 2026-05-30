import SwiftUI

struct BereanPulseEmptyStateView: View {
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            AmenGlass3DIcon(
                systemName: "sparkles.rectangle.stack",
                tint: AmenTheme.Colors.amenPurple,
                size: 72
            )
            .accessibilityHidden(true)

            Text(String(localized: "No Pulse cards are ready yet"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(String(localized: "Refresh to ask Berean for new cards. If nothing appears, Berean does not have enough current context to show a useful next step."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onRefresh) {
                Label(String(localized: "Refresh Pulse"), systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(Color.primary, in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Checks for newly available Berean Pulse cards."))
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}
