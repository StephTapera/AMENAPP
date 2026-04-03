import SwiftUI
import FirebaseAuth

/// Threads-style inline composer pinned below the Daily Verse Banner in OpenTable.
/// Tap expands to an inline text field; typing and tapping "Post" quick-posts.
/// The expand icon opens the full CreatePostView via onTap for media/rich posts.
struct FeedComposerRow: View {
    let onTap: () -> Void

    @ObservedObject private var userService = LegacyUserService.shared
    @State private var placeholder = "What's on your heart today?"
    @State private var text = ""
    @State private var isExpanded = false
    @State private var isPosting = false
    @FocusState private var isFocused: Bool

    private var avatarURL: URL? {
        let raw = userService.currentUser?.profileImageURL
            ?? UserDefaults.standard.string(forKey: "currentUserProfileImageURL")
        guard let raw, !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {

                // ── Avatar ──
                composerAvatar
                    .padding(.leading, 10)

                if isExpanded {
                    // ── Inline text field ──
                    TextField(placeholder, text: $text, axis: .vertical)
                        .font(.systemScaled(15, weight: .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1...5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .focused($isFocused)
                        .submitLabel(.done)

                    // ── Expand to full composer ──
                    Button {
                        dismissKeyboard()
                        isExpanded = false
                        text = ""
                        onTap()
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.systemScaled(13, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.4))
                            .padding(.trailing, 10)
                    }

                    // ── Hairline ──
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 0.5, height: 22)

                    // ── Post button ──
                    Button {
                        submitPost()
                    } label: {
                        if isPosting {
                            ProgressView()
                                .scaleEffect(0.75)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                        } else {
                            Text("Post")
                                .font(.systemScaled(13, weight: .semibold))
                                .foregroundStyle(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? Color.primary.opacity(0.22)
                                    : Color.primary.opacity(0.85))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                        }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPosting)

                } else {
                    // ── Collapsed placeholder ──
                    Text(placeholder)
                        .font(.systemScaled(15, weight: .regular))
                        .foregroundStyle(.primary.opacity(0.28))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .animation(.easeInOut(duration: 0.3), value: placeholder)
                        .onTapGesture { expand() }

                    // ── Hairline divider ──
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 0.5, height: 22)

                    // ── Post label ──
                    Text("Post")
                        .font(.systemScaled(13, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.22))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .onTapGesture { expand() }
                }
            }
            .frame(minHeight: 52)
            .background(GlassPillBackground(isPressing: false))
            .clipShape(Capsule())
            .contentShape(Capsule())
            .onTapGesture { if !isExpanded { expand() } }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: isExpanded)
        .task {
            guard let uid = Auth.auth().currentUser?.uid else { return }
            let t = await ComposerPlaceholderService.shared.getPlaceholder(for: uid)
            withAnimation(.easeInOut(duration: 0.3)) { placeholder = t }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused && text.isEmpty {
                withAnimation(Motion.adaptive(.spring(response: 0.32, dampingFraction: 0.72))) {
                    isExpanded = false
                }
            }
        }
    }

    // MARK: - Actions

    private func expand() {
        withAnimation(Motion.adaptive(.spring(response: 0.32, dampingFraction: 0.72))) {
            isExpanded = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isFocused = true
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func submitPost() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isPosting = true
        dismissKeyboard()
        PostsManager.shared.createPost(content: trimmed, category: .openTable)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(Motion.adaptive(.spring(response: 0.32, dampingFraction: 0.72))) {
            text = ""
            isExpanded = false
            isPosting = false
        }
    }

    private func dismissKeyboard() {
        isFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }

    // MARK: - Avatar

    @ViewBuilder
    private var composerAvatar: some View {
        Group {
            if let url = avatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        avatarFallback
                    }
                }
            } else {
                avatarFallback
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }

    private var avatarFallback: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.systemScaled(14, weight: .regular))
                    .foregroundStyle(.primary.opacity(0.35))
            )
    }
}

// MARK: - Glass Capsule Background

private struct GlassPillBackground: View {
    let isPressing: Bool

    var body: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isPressing ? 0.25 : 0.55),
                                Color.white.opacity(isPressing ? 0.05 : 0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: .black.opacity(0.07), radius: 12, x: 0, y: 4)
            .shadow(color: .black.opacity(0.04), radius: 2,  x: 0, y: 1)
    }
}
