//
//  SharedUIComponents.swift
//  AMENAPP
//
//  Created by Steph on 2/1/26.
//
//  Shared UI components for loading states, empty states, and error handling
//

import SwiftUI

// MARK: - AMEN Loading Indicator (3-dot bounce)

/// Reusable 3-dot bouncing loading indicator.
/// Use this everywhere in the app instead of ProgressView() for content-loading states.
///
/// Usage:
///   AMENLoadingIndicator()                    // default (primary color, medium size)
///   AMENLoadingIndicator(color: .white)       // white dots (dark backgrounds)
///   AMENLoadingIndicator(dotSize: 8)          // smaller dots for tight spaces
struct AMENLoadingIndicator: View {
    var color: Color = .primary
    var dotSize: CGFloat = 9
    var spacing: CGFloat = 8
    var bounceHeight: CGFloat = 10
    var animDuration: Double = 0.46

    @State private var dot1Up = false
    @State private var dot2Up = false
    @State private var dot3Up = false

    var body: some View {
        HStack(spacing: spacing) {
            dot(isUp: dot1Up)
            dot(isUp: dot2Up)
            dot(isUp: dot3Up)
        }
        .onAppear { startBouncing() }
    }

    private func dot(isUp: Bool) -> some View {
        Circle()
            .fill(color)
            .frame(width: dotSize, height: dotSize)
            .offset(y: isUp ? -bounceHeight : 0)
            .animation(
                .easeInOut(duration: animDuration).repeatForever(autoreverses: true),
                value: isUp
            )
    }

    private func startBouncing() {
        let stagger = animDuration * 0.55
        withAnimation(.easeInOut(duration: animDuration).repeatForever(autoreverses: true)) {
            dot1Up = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(stagger))
            withAnimation(.easeInOut(duration: animDuration).repeatForever(autoreverses: true)) {
                dot2Up = true
            }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(stagger * 2))
            withAnimation(.easeInOut(duration: animDuration).repeatForever(autoreverses: true)) {
                dot3Up = true
            }
        }
    }
}

// MARK: - Loading Skeleton Views

/// Skeleton loader for post cards while data is loading.
/// Matches PostCard's exact layout: flat background, Threads-style divider,
/// header row (40 pt avatar + name/timestamp), 3 body text lines, icon action bar.
struct PostSkeletonView: View {
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Shimmer fill — matches PostCard's Color(.systemBackground) surface
    private let shimmerStrong = Color.gray.opacity(0.2)
    private let shimmerLight  = Color.gray.opacity(0.13)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header row (mirrors postHeaderView padding: h:12, top:4, bottom:10) ──
            HStack(spacing: 12) {
                // Avatar circle — 40 pt, same as avatarButton
                Circle()
                    .fill(shimmerStrong)
                    .frame(width: 40, height: 40)

                // Author name + timestamp stack
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(shimmerStrong)
                        .frame(width: 120, height: 13)   // name line
                    RoundedRectangle(cornerRadius: 4)
                        .fill(shimmerLight)
                        .frame(width: 80, height: 11)    // timestamp line
                }

                Spacer()

                // Options button placeholder (•••)
                RoundedRectangle(cornerRadius: 4)
                    .fill(shimmerLight)
                    .frame(width: 20, height: 16)
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 10)

            // ── Body text lines (mirrors postContentWithSelection padding h:16) ──
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(shimmerStrong)
                    .frame(maxWidth: .infinity)
                    .frame(height: 14)
                RoundedRectangle(cornerRadius: 4)
                    .fill(shimmerStrong)
                    .frame(maxWidth: .infinity)
                    .frame(height: 14)
                RoundedRectangle(cornerRadius: 4)
                    .fill(shimmerLight)
                    .frame(width: 200, height: 14)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            // ── Interaction bar (mirrors interactionButtons padding h:16, top:14, bottom:16) ──
            // PostCard shows icon-style buttons (~20 pt), not capsules.
            HStack(spacing: 20) {
                // Lightbulb / Amen icon
                Circle()
                    .fill(shimmerLight)
                    .frame(width: 22, height: 22)
                // Emoji reaction icon
                Circle()
                    .fill(shimmerLight)
                    .frame(width: 22, height: 22)
                // Comment icon
                Circle()
                    .fill(shimmerLight)
                    .frame(width: 22, height: 22)
                // Repost icon
                Circle()
                    .fill(shimmerLight)
                    .frame(width: 22, height: 22)
                // Share / save icon
                Circle()
                    .fill(shimmerLight)
                    .frame(width: 22, height: 22)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 16)

            // Threads-style bottom divider (mirrors PostCard's .overlay divider)
            Rectangle()
                .fill(Color(.separator).opacity(0.5))
                .frame(height: 0.5)
        }
        .background(Color(.systemBackground))
        .opacity(isAnimating ? 0.5 : 1.0)
        .animation(
            .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
            value: isAnimating
        )
        .accessibilityHidden(true)
        .onAppear {
            if !reduceMotion {
                isAnimating = true
            }
        }
    }
}

/// Skeleton loader for list of posts.
/// Uses spacing: 0 to match the Threads-style feed where PostCard renders its
/// own bottom divider — no card gap or outer padding needed.
struct PostListSkeletonView: View {
    var count: Int = 5

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { _ in
                PostSkeletonView()
            }
        }
    }
}

/// Compact skeleton for smaller items (messages, notifications)
struct CompactSkeletonView: View {
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 44, height: 44)
            
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 150, height: 12)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 200, height: 10)
            }
            
            Spacer()
        }
        .padding()
        .opacity(isAnimating ? 0.5 : 1.0)
        .animation(
            .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
            value: isAnimating
        )
        .onAppear {
            if !reduceMotion {
                isAnimating = true
            }
        }
    }
}

// MARK: - Empty State Views

/// Empty state for posts feed
struct EmptyPostsView: View {
    var category: String = "posts"
    
    var body: some View {
        EmptyStateView(
            icon: "doc.text",
            title: "No \(category.capitalized) Yet",
            subtitle: "Be the first to share and inspire the community!"
        )
    }
}

/// Empty state for messages
struct EmptyMessagesView: View {
    var body: some View {
        EmptyStateView(
            icon: "bubble.left.and.bubble.right",
            title: "No Messages",
            subtitle: "Start a conversation with someone you follow"
        )
    }
}

/// Empty state for notifications
struct EmptyNotificationsView: View {
    var body: some View {
        EmptyStateView(
            icon: "bell",
            title: "No Notifications",
            subtitle: "When someone interacts with your posts, you'll see it here"
        )
    }
}

/// Empty state for search results
struct EmptySearchView: View {
    var searchQuery: String
    
    var body: some View {
        EmptyStateView(
            icon: "magnifyingglass",
            title: "No Results",
            subtitle: "We couldn't find anything matching '\(searchQuery)'"
        )
    }
}

// MARK: - Error Toast System

enum ToastType {
    case success
    case error
    case info
    case warning
    
    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .success: return .green
        case .error: return .red
        case .info: return .blue
        case .warning: return .orange
        }
    }
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let type: ToastType
    let message: String
    var duration: TimeInterval = 3.0
    
    static func == (lhs: Toast, rhs: Toast) -> Bool {
        lhs.id == rhs.id
    }
}

struct ToastView: View {
    let toast: Toast
    @State private var offset: CGFloat = -100
    @State private var opacity: Double = 0
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.type.icon)
                .font(.systemScaled(20, weight: .semibold))
                .foregroundColor(.white)
            
            Text(toast.message)
                .font(AMENFont.semiBold(14))
                .foregroundColor(.white)
                .lineLimit(2)
            
            Spacer(minLength: 0)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(toast.type.color)
                .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
        )
        .padding(.horizontal)
        .offset(y: offset)
        .opacity(opacity)
        .onAppear {
            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.7))) {
                offset = 0
                opacity = 1
            }
        }
    }
}

struct ToastModifier: ViewModifier {
    @Binding var toast: Toast?
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            if let toast = toast {
                VStack {
                    ToastView(toast: toast)
                        .padding(.top, 50)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    
                    Spacer()
                }
                .zIndex(999)
                .onAppear {
                    // Auto-dismiss after specified duration
                    DispatchQueue.main.asyncAfter(deadline: .now() + toast.duration) {
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                            self.toast = nil
                        }
                    }
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: toast)
    }
}

extension View {
    /// Add toast notification capability to any view
    func toast(_ toast: Binding<Toast?>) -> some View {
        modifier(ToastModifier(toast: toast))
    }
}

// MARK: - Loading Overlay

struct LoadingOverlay: View {
    var message: String = "Loading..."
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                AMENLoadingIndicator(color: .white)
                
                Text(message)
                    .font(AMENFont.semiBold(14))
                    .foregroundColor(.white)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.8))
            )
        }
    }
}

struct LoadingOverlayModifier: ViewModifier {
    @Binding var isLoading: Bool
    var message: String
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            if isLoading {
                LoadingOverlay(message: message)
                    .transition(.opacity)
            }
        }
    }
}

extension View {
    /// Add a loading overlay to any view
    func loadingOverlay(isLoading: Binding<Bool>, message: String = "Loading...") -> some View {
        modifier(LoadingOverlayModifier(isLoading: isLoading, message: message))
    }
}

// MARK: - Error View

struct ErrorView: View {
    let error: Error
    var retryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.systemScaled(48))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text("Something Went Wrong")
                .font(AMENFont.bold(18))
                .foregroundStyle(.primary)

            Text(error.userFriendlyMessage)
                .font(AMENFont.regular(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if let retryAction = retryAction {
                Button(action: retryAction) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                            .accessibilityHidden(true)
                        Text("Try Again")
                    }
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.primary)
                    .cornerRadius(25)
                }
                .accessibilityLabel("Try Again")
                .accessibilityHint("Retry the failed operation")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Inline Error Banner
// Note: This component is defined in ComponentsSharedUIComponents.swift
// If you see redeclaration errors, check for duplicate definitions in other files

struct SharedUIInlineErrorBanner: View {
    let message: String
    var retryAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text(message)
                .font(AMENFont.regular(13))
                .foregroundStyle(.primary)
                .lineLimit(2)
            
            Spacer()
            
            if let retryAction = retryAction {
                Button(action: retryAction) {
                    Image(systemName: "arrow.clockwise")
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal)
    }
}

// MARK: - Preview Helpers

#Preview("Post Skeleton") {
    PostSkeletonView()
        .padding()
}

#Preview("Empty Posts") {
    EmptyPostsView(category: "testimonies")
}

#Preview("Toast") {
    VStack {
        Spacer()
    }
    .toast(.constant(Toast(type: .success, message: "Post created successfully!")))
}

#Preview("Loading Overlay") {
    Color.gray.opacity(0.2)
        .loadingOverlay(isLoading: .constant(true))
}

#Preview("Error View") {
    ErrorView(
        error: NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Network connection lost"]),
        retryAction: {}
    )
}
