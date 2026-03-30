//
//  SpotlightCard.swift
//  AMENAPP
//
//  Spotlight content card with dark frosted glass design
//  Matches modern iOS glassmorphic aesthetic
//

import SwiftUI
import FirebaseAuth

struct SpotlightCard: View {
    let post: Post
    let explanation: String?
    
    @State private var isPressed = false
    @State private var showPostDetail = false
    @State private var hasReacted = false
    @State private var showShareSheet = false
    
    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showPostDetail = true
        }) {
            VStack(alignment: .leading, spacing: 14) {
                // Author header
                authorHeader
                
                // Category badge (if not OpenTable)
                if post.category != .openTable {
                    categoryBadge
                }
                
                // Content
                Text(post.content)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.white)
                    .lineLimit(8)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Media if present
                if let imageURLs = post.imageURLs, let firstImage = imageURLs.first {
                    postImage(url: firstImage)
                }
                
                // Spotlight explanation
                if let explanation = explanation {
                    spotlightExplanation(explanation)
                }
                
                // Interaction bar
                interactionBar
            }
            .padding(16)
            .background(darkFrostedCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .sheet(isPresented: $showPostDetail) {
            PostDetailView(post: post)
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [generateShareText()])
        }
    }
    
    // MARK: - Author Header
    
    private var authorHeader: some View {
        HStack(spacing: 12) {
            // Profile image
            if let profileImageURL = post.authorProfileImageURL {
                CachedAsyncImage(url: URL(string: profileImageURL)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                } placeholder: {
                    authorInitialsCircle
                }
            } else {
                authorInitialsCircle
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(post.authorName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(post.timeAgo)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            // More menu
            Button(action: {
                // Show action menu
            }) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 32, height: 32)
            }
        }
    }
    
    private var authorInitialsCircle: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Color.amenGold.opacity(0.5), Color.amenBronze.opacity(0.5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 40, height: 40)
            .overlay(
                Text(post.authorInitials)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            )
    }
    
    // MARK: - Category Badge
    
    private var categoryBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: categoryIcon)
                .font(.system(size: 12, weight: .medium))
            
            Text(categoryName)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundColor(categoryColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(categoryColor.opacity(0.12))
        )
    }
    
    private var categoryIcon: String {
        switch post.category {
        case .prayer: return "hands.sparkles.fill"
        case .testimonies: return "star.bubble.fill"
        case .openTable: return "bubble.left.and.bubble.right.fill"
        case .tip: return "lightbulb.fill"
        case .funFact: return "sparkles"
        }
    }
    
    private var categoryName: String {
        switch post.category {
        case .prayer: return "Prayer"
        case .testimonies: return "Testimony"
        case .openTable: return ""
        case .tip: return "Tip"
        case .funFact: return "Fun Fact"
        }
    }
    
    private var categoryColor: Color {
        switch post.category {
        case .prayer: return .blue
        case .testimonies: return .yellow
        case .openTable: return .primary
        case .tip: return .green
        case .funFact: return .orange
        }
    }
    
    // MARK: - Post Image
    
    private func postImage(url: String) -> some View {
        CachedAsyncImage(url: URL(string: url)) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } placeholder: {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.05))
                .frame(height: 220)
                .overlay(
                    ProgressView()
                        .tint(.secondary)
                )
        }
    }
    
    // MARK: - Spotlight Explanation
    
    private func spotlightExplanation(_ text: String) -> some View {
        HStack(spacing: 8) {
            // White lightbulb icon
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
            
            // Orange text
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.orange)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(
            ZStack {
                // Black glassmorphic background
                Capsule()
                    .fill(Color.black.opacity(0.6))
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                    )
                
                // Transparent liquid glass border
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.3),
                                .white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            }
        )
    }
    
    // MARK: - Interaction Bar
    
    private var interactionBar: some View {
        HStack(spacing: 20) {
            // Lightbulb (like)
            InteractionButton(
                icon: hasReacted ? "lightbulb.fill" : "lightbulb",
                count: post.lightbulbCount,
                color: hasReacted ? .amenGold : .white.opacity(0.6),
                action: {
                    withAnimation(LiquidSpring.elastic) {
                        hasReacted.toggle()
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            )
            
            // Comments
            InteractionButton(
                icon: "bubble.left",
                count: post.commentCount,
                color: .white.opacity(0.6),
                action: {
                    showPostDetail = true
                }
            )
            
            // Share
            InteractionButton(
                icon: "paperplane",
                count: post.repostCount,
                color: .white.opacity(0.6),
                action: {
                    showShareSheet = true
                }
            )
            
            Spacer()
            
            // Bookmark
            Button(action: {}) {
                Image(systemName: "bookmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.top, 4)
    }
    
    // MARK: - Card Background
    
    private var darkFrostedCardBackground: some View {
        ZStack {
            // Base frosted glass
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
            
            // Dark tinted overlay
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.15),
                            Color.white.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Subtle inner glow
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.05),
                            Color.clear
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
        }
    }
    
    // MARK: - Helper Functions
    
    private func generateShareText() -> String {
        "\(post.content)\n\n- \(post.authorName) on AMEN"
    }
}

// MARK: - Interaction Button

struct InteractionButton: View {
    let icon: String
    let count: Int
    let color: Color
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(color)
                
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(color)
                }
            }
            .scaleEffect(isPressed ? 1.15 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Preview
// Preview removed - use app simulator to test Spotlight feature

