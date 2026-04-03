import SwiftUI

/// Liquid glass byline strip shown above a repost card.
/// Shows reposter avatar + name + "reposted" label + optional New badge.
struct RepostBylineStrip: View {
    let reposterName: String
    let reposterAvatarURL: String?
    var isNew: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.2.squarepath")
                .font(.systemScaled(9, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.55))

            // Reposter avatar
            Group {
                if let urlStr = reposterAvatarURL, !urlStr.isEmpty, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: avatarPlaceholder
                        }
                    }
                } else {
                    avatarPlaceholder
                }
            }
            .frame(width: 14, height: 14)
            .clipShape(Circle())

            Text("\(reposterName) reposted")
                .font(.systemScaled(8.5))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            if isNew {
                RepostNewBadge()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.75), lineWidth: 0.5)
                )
        )
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(Color.orange.opacity(0.7))
            .overlay(
                Text(String(reposterName.prefix(1)).uppercased())
                    .font(.systemScaled(7, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

/// Pulsing "New" badge for reposts.
private struct RepostNewBadge: View {
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 3) {
            ZStack {
                Circle()
                    .stroke(Color.orange.opacity(0.4), lineWidth: 1)
                    .frame(width: pulse ? 9 : 5, height: pulse ? 9 : 5)
                    .opacity(pulse ? 0 : 0.9)
                Circle()
                    .fill(Color.orange)
                    .frame(width: 5, height: 5)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 2).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
            Text("New")
                .font(.systemScaled(8, weight: .bold))
                .foregroundStyle(Color.orange)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.1), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.orange.opacity(0.25), lineWidth: 0.5))
    }
}
