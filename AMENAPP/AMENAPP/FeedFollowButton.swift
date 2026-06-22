import SwiftUI
// MARK: - Follow Button

struct FollowButton: View {
    @Binding var isFollowing: Bool
    @State private var isPressed = false
    
    var body: some View {
        Button {
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.6))) {
                isFollowing.toggle()
                
                HapticManager.impact(style: isFollowing ? .medium : .light)
            }
        } label: {
            buttonContent
                .scaleEffect(isPressed ? 0.92 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        withAnimation(.easeIn(duration: 0.1)) {
                            isPressed = true
                        }
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.1)) {
                        isPressed = false
                    }
                }
        )
    }
    
    private var buttonContent: some View {
        HStack(spacing: 4) {
            if !isFollowing {
                Image(systemName: "plus")
                    .font(.systemScaled(10, weight: .bold))
            }
            Text(isFollowing ? "Following" : "Follow")
                .font(AMENFont.bold(12))
        }
        .foregroundStyle(isFollowing ? Color.secondary : Color.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(buttonBackground)
    }
    
    private var buttonBackground: some View {
        Capsule()
            .fill(isFollowing ? Color.clear : Color.black)
            .overlay(
                Capsule()
                    .stroke(isFollowing ? Color.secondary.opacity(0.3) : Color.clear, lineWidth: 1)
            )
    }
}

// MARK: - Category Views

// Environment key for toolbar visibility
struct ToolbarVisibleKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(true)
}

extension EnvironmentValues {
    var toolbarVisible: Binding<Bool> {
        get { self[ToolbarVisibleKey.self] }
        set { self[ToolbarVisibleKey.self] = newValue }
    }
}

/// PreferenceKey for detecting scroll position in the feed LazyVStack
struct FeedScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
