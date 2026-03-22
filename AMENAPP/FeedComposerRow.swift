import SwiftUI
import FirebaseAuth

/// Tappable composer row pinned below the Daily Verse Banner in OpenTable.
/// Tapping anywhere opens CreatePostView via the provided action closure.
struct FeedComposerRow: View {
    let onTap: () -> Void

    @ObservedObject private var userService = LegacyUserService.shared
    @State private var isPressed = false

    private var avatarURL: String? {
        userService.currentUser?.profileImageURL
            ?? UserDefaults.standard.string(forKey: "currentUserProfileImageURL")
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Avatar
                Group {
                    if let url = avatarURL, !url.isEmpty, let parsed = URL(string: url) {
                        AsyncImage(url: parsed) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().scaledToFill()
                            default:
                                placeholderAvatar
                            }
                        }
                    } else {
                        placeholderAvatar
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())

                // Prompt text
                Text("What's on your heart?")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Post button
                Text("Post")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.accentColor))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
            }
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }

    private var placeholderAvatar: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.2))
            .overlay(
                Text(userService.currentUser?.initials ?? "?")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            )
    }
}
