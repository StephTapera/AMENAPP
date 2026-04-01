import SwiftUI

/// Single Liquid Glass entry banner for AMEN Connect.
/// Replaces the previous multi-card scatter in ResourcesView.
struct AMENConnectBanner: View {

    @State private var isPressed = false

    private let featurePills = ["Network", "Serve", "Jobs", "Ministries", "Conversations"]

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color(white: 0.82).opacity(0.45), lineWidth: 0.5)
                    )
                    .frame(width: 52, height: 52)

                Image(systemName: "person.2.wave.2.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.75))
            }

            // Text + pills
            VStack(alignment: .leading, spacing: 6) {
                Text("AMEN Connect")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.primary)

                Text("Find your people, serve, and grow together.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                // Feature pill row
                HStack(spacing: 6) {
                    ForEach(featurePills.prefix(3), id: \.self) { pill in
                        Text(pill)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.black.opacity(0.55))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.05))
                            )
                    }
                    Text("+\(featurePills.count - 3)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.black.opacity(0.35))
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.58))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.07), radius: 14, x: 0, y: 5)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded   { _ in isPressed = false }
        )
    }
}

struct AMENConnectBanner_Previews: PreviewProvider {
    static var previews: some View {
        AMENConnectBanner()
            .padding(20)
            .background(Color(white: 0.97))
            .previewLayout(.sizeThatFits)
    }
}
