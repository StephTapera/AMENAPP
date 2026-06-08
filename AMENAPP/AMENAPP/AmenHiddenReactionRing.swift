import SwiftUI

struct AmenHiddenReactionRing: View {
    let reactions: [AmenReactionKind]
    let onSelect: (AmenReactionKind) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().fill(Color.white.opacity(0.88)))
                    .frame(width: 176, height: 176)
                    .shadow(color: .black.opacity(0.08), radius: 20, y: 8)

                ForEach(Array(reactions.enumerated()), id: \.offset) { index, reaction in
                    let angle = Angle.degrees(Double(index) / Double(max(reactions.count, 1)) * 360.0 - 90.0)
                    let radius: CGFloat = 62

                    Button {
                        onSelect(reaction)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: reaction.systemImage)
                                .font(.systemScaled(15, weight: .semibold))
                            Text(reaction.title)
                                .font(.systemScaled(10, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.black.opacity(0.84))
                        .frame(width: 52, height: 52)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay(Circle().fill(Color.white.opacity(0.88)))
                        )
                    }
                    .buttonStyle(.plain)
                    .offset(
                        x: CGFloat(cos(angle.radians)) * radius,
                        y: CGFloat(sin(angle.radians)) * radius
                    )
                }
            }
        }
        .transition(.opacity.combined(with: .scale))
        .accessibilityElement(children: .contain)
    }
}
