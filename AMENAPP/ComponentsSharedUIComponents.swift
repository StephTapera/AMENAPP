//
//  SharedUIComponents.swift
//  AMENAPP
//
//  Created by Steph on 2/1/26.
//
//  Shared UI components for loading states, empty states, and error handling
//

import SwiftUI

// MARK: - Loading Skeleton Views

/// Skeleton loader for post cards while data is loading
struct PostSkeletonView: View {
    @State private var isAnimating = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header (profile + name)
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 40, height: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 120, height: 12)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 80, height: 10)
                }
                
                Spacer()
            }
            
            // Content lines
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 14)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 14)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 200, height: 14)
            }
            .padding(.vertical, 4)
            
            // Interaction buttons
            HStack(spacing: 12) {
                ForEach(0..<4) { _ in
                    Capsule()
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 60, height: 28)
                }
                
                Spacer()
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 8, y: 2)
        )
        .opacity(isAnimating ? 0.5 : 1.0)
        .animation(
            .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
            value: isAnimating
        )
        .onAppear {
            isAnimating = true
        }
    }
}

/// Skeleton loader for list of posts
struct PostListSkeletonView: View {
    var count: Int = 5
    
    var body: some View {
        VStack(spacing: 16) {
            ForEach(0..<count, id: \.self) { _ in
                PostSkeletonView()
            }
        }
        .padding()
    }
}

/// Compact skeleton for smaller items (messages, notifications)
struct CompactSkeletonView: View {
    @State private var isAnimating = false
    
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
            isAnimating = true
        }
    }
}

// MARK: - Empty State Views

/// Generic empty state view with icon, title, and message
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var buttonTitle: String? = nil
    var buttonAction: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 64, weight: .light))
                .foregroundColor(.gray.opacity(0.4))
                .padding(.bottom, 8)
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 20))
                    .foregroundColor(.black)
                
                Text(message)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            if let buttonTitle = buttonTitle, let buttonAction = buttonAction {
                Button(action: buttonAction) {
                    Text(buttonTitle)
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.black)
                        .cornerRadius(25)
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
    }
}

/// Empty state for posts feed
struct EmptyPostsView: View {
    var category: String = "posts"
    
    var body: some View {
        EmptyStateView(
            icon: "doc.text",
            title: "No \(category.capitalized) Yet",
            message: "Be the first to share and inspire the community!"
        )
    }
}

/// Empty state for messages
struct EmptyMessagesView: View {
    var body: some View {
        EmptyStateView(
            icon: "bubble.left.and.bubble.right",
            title: "No Messages",
            message: "Start a conversation with someone you follow"
        )
    }
}

/// Empty state for notifications
struct EmptyNotificationsView: View {
    var body: some View {
        EmptyStateView(
            icon: "bell",
            title: "No Notifications",
            message: "When someone interacts with your posts, you'll see it here"
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
            message: "We couldn't find anything matching '\(searchQuery)'"
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
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
            
            Text(toast.message)
                .font(.custom("OpenSans-SemiBold", size: 14))
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
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
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
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
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
                ProgressView()
                    .scaleEffect(1.2)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                
                Text(message)
                    .font(.custom("OpenSans-SemiBold", size: 14))
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
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("Something Went Wrong")
                .font(.custom("OpenSans-Bold", size: 18))
                .foregroundColor(.black)
            
            Text(error.localizedDescription)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            if let retryAction = retryAction {
                Button(action: retryAction) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("Try Again")
                    }
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.black)
                    .cornerRadius(25)
                }
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
                .foregroundColor(.orange)
            
            Text(message)
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundColor(.black)
                .lineLimit(2)
            
            Spacer()
            
            if let retryAction = retryAction {
                Button(action: retryAction) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
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
