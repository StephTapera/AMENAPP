import SwiftUI

// MARK: - Post Success Toast (Glassmorphic Design)

// MARK: - Posting Bar State

enum PostingBarState: Equatable {
    case hidden
    case posting   // spinner + "Posting…"
    case posted    // checkmark + "Posted · View"
}

// MARK: - ThreadsPostingBar

/// Threads-style bottom bar that slides up from the tab bar.
/// Shows "Posting…" while the network call is in flight, then
/// transitions to "Posted · View" once Firestore confirms.
struct ThreadsPostingBar: View {
    let state: PostingBarState
    let category: String
    let post: Post?
    let onView: () -> Void

    // Category-specific accent
    private var accent: Color {
        switch category {
        case "openTable":   return .orange
        case "testimonies": return .yellow
        case "prayer":      return .blue
        default:            return Color.accentColor
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            // Left: app icon circle
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 36, height: 36)
                Image("amen-logo")
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
            }

            // Middle: label
            Group {
                if state == .posting {
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.75)
                            .tint(.secondary)
                        Text("Posting…")
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.systemScaled(15, weight: .semibold))
                            .foregroundStyle(.green)
                            .symbolEffect(.bounce, value: state == .posted)
                        Text("Posted")
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state)

            Spacer()

            // Right: "View" button (only when posted)
            if state == .posted {
                Button(action: onView) {
                    Text("View")
                        .font(.systemScaled(15, weight: .semibold))
                        .foregroundStyle(accent)
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: .black.opacity(0.18), radius: 24, y: 6)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: state)
        .onAppear {
            if state == .posted {
                HapticManager.notification(type: .success)
            }
        }
        .onChange(of: state) { _, newState in
            if newState == .posted {
                HapticManager.notification(type: .success)
            }
        }
    }
}

// Keep PostSuccessToast as a thin alias so any lingering references still compile
@available(*, deprecated, renamed: "ThreadsPostingBar")
struct PostSuccessToast: View {
    let category: String
    @State private var isAnimating = false
    
    // Category display info
    private var categoryInfo: (icon: String, name: String, color: Color) {
        switch category {
        case "openTable":
            return ("lightbulb.fill", "#OPENTABLE", .orange)
        case "testimonies":
            return ("star.fill", "Testimonies", .yellow)
        case "prayer":
            return ("hands.sparkles.fill", "Prayer", .blue)
        default:
            return ("checkmark.circle.fill", "Post", .green)
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Success icon with subtle animation
            ZStack {
                // Outer pulse ring
                Circle()
                    .fill(categoryInfo.color.opacity(0.2))
                    .frame(width: 40, height: 40)
                    .scaleEffect(isAnimating ? 1.2 : 1.0)
                    .opacity(isAnimating ? 0 : 1)
                
                // Inner circle with glassmorphic effect
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.5),
                                        Color.white.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                
                // Icon
                Image(systemName: categoryInfo.icon)
                    .font(.systemScaled(16, weight: .semibold))
                    .foregroundStyle(categoryInfo.color)
                    .symbolEffect(.bounce, value: isAnimating)
            }
            
            // Text content
            VStack(alignment: .leading, spacing: 2) {
                Text("Posted to \(categoryInfo.name)")
                    .font(AMENFont.bold(14))
                    .foregroundStyle(.primary)
                
                Text("Your post is now live")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Checkmark
            Image(systemName: "checkmark.circle.fill")
                .font(.systemScaled(20))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: isAnimating)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            ZStack {
                // Glassmorphic background
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                
                // Subtle gradient overlay
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.15),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Border with gradient
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.4),
                                Color.white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
        .shadow(color: categoryInfo.color.opacity(0.2), radius: 12, y: 4)
        .padding(.horizontal, 20)
        .onAppear {
            // Trigger animations
            withAnimation(.easeOut(duration: 0.6)) {
                isAnimating = true
            }
            
            // Haptic feedback
            HapticManager.notification(type: .success)
        }
    }
}
