//
//  ReplyThreadRowView.swift
//  AMENAPP
//
//  Row view for displaying a reply thread (original post + user's reply)
//  Matches Threads-style threading with vertical connector line
//

import SwiftUI

struct ReplyThreadRowView: View {
    let thread: ReplyThread
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Original post (dimmed)
            originalPostSection
            
            // Vertical connector line
            connectorLine
            
            // User's reply
            userReplySection
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.clear)
                .background(.ultraThinMaterial)
                .background(
                    LinearGradient(
                        colors: [
                            Color(.systemBackground).opacity(0.05),
                            Color(.systemBackground).opacity(0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.primary.opacity(0.1),
                                    Color.primary.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
                .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 2)
        )
    }
    
    // MARK: - Original Post Section (Dimmed)
    
    private var originalPostSection: some View {
        HStack(alignment: .top, spacing: 12) {
            // Author avatar
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.secondary.opacity(0.2),
                            Color.secondary.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 40, height: 40)
                .overlay(
                    Text(thread.originalPost.authorInitials)
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(.secondary.opacity(0.6))
                )
            
            VStack(alignment: .leading, spacing: 6) {
                // Author name and username
                HStack(spacing: 6) {
                    Text(thread.originalPost.authorName)
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(.secondary.opacity(0.7))
                    
                    if let username = thread.originalPost.authorUsername {
                        Text("@\(username)")
                            .font(AMENFont.regular(14))
                            .foregroundStyle(.secondary.opacity(0.5))
                    }
                    
                    Spacer()
                    
                    Text(thread.originalPost.timeAgo)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
                
                // Post content (truncated if long)
                Text(thread.originalPost.content)
                    .font(AMENFont.regular(15))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                
                // Category badge
                categoryBadge
            }
        }
    }
    
    // MARK: - Connector Line
    
    private var connectorLine: some View {
        HStack(spacing: 0) {
            // Left margin to align with avatar
            Color.clear
                .frame(width: 20)
            
            // Vertical line
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.primary.opacity(0.15),
                            Color.primary.opacity(0.08)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 2, height: 20)
            
            Spacer()
        }
    }
    
    // MARK: - User Reply Section
    
    private var userReplySection: some View {
        HStack(alignment: .top, spacing: 12) {
            // User avatar
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.25),
                            Color.blue.opacity(0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 40, height: 40)
                .overlay(
                    Circle()
                        .strokeBorder(Color.blue.opacity(0.3), lineWidth: 1)
                )
                .overlay(
                    Text(thread.userReply.authorInitials)
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(.primary)
                )
            
            VStack(alignment: .leading, spacing: 6) {
                // User name and username
                HStack(spacing: 6) {
                    Text(thread.userReply.authorName)
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(.primary)
                    
                    Text("@\(thread.userReply.authorUsername)")
                        .font(AMENFont.regular(14))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Text(thread.userReply.timeAgo)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                }
                
                // Reply content
                Text(thread.userReply.content)
                    .font(AMENFont.regular(15))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                
                // Reply stats
                replyStats
            }
        }
    }
    
    // MARK: - Category Badge
    
    private var categoryBadge: some View {
        Group {
            if thread.originalPost.category.showCategoryBadge {
                Text(thread.originalPost.category.displayName)
                    .font(AMENFont.bold(11))
                    .foregroundStyle(categoryColor.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(categoryColor.opacity(0.12))
                            .overlay(
                                Capsule()
                                    .strokeBorder(categoryColor.opacity(0.2), lineWidth: 0.5)
                            )
                    )
            }
        }
    }
    
    // MARK: - Reply Stats
    
    private var replyStats: some View {
        HStack(spacing: 16) {
            // Amen count
            if thread.userReply.amenCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "hands.sparkles.fill")
                        .font(.systemScaled(13))
                        .foregroundStyle(.secondary.opacity(0.7))
                    
                    Text("\(thread.userReply.amenCount)")
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                }
            }
            
            // Reply count
            if thread.userReply.replyCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "bubble.left.fill")
                        .font(.systemScaled(13))
                        .foregroundStyle(.secondary.opacity(0.7))
                    
                    Text("\(thread.userReply.replyCount)")
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 4)
    }
    
    // MARK: - Helpers
    
    private var categoryColor: Color {
        switch thread.originalPost.category {
        case .openTable:
            return .white
        case .testimonies:
            return .yellow
        case .prayer:
            return .purple
        case .tip:
            return .green
        case .funFact:
            return .orange
        }
    }
}
