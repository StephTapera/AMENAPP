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
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    // MARK: - Original Post Section (Dimmed)
    
    private var originalPostSection: some View {
        HStack(alignment: .top, spacing: 12) {
            // Author avatar
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(thread.originalPost.authorInitials)
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundColor(.white.opacity(0.5))
                )
            
            VStack(alignment: .leading, spacing: 6) {
                // Author name and username
                HStack(spacing: 6) {
                    Text(thread.originalPost.authorName)
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .foregroundColor(.white.opacity(0.5))
                    
                    if let username = thread.originalPost.authorUsername {
                        Text("@\(username)")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    
                    Spacer()
                    
                    Text(thread.originalPost.timeAgo)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundColor(.white.opacity(0.4))
                }
                
                // Post content (truncated if long)
                Text(thread.originalPost.content)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundColor(.white.opacity(0.5))
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
                .fill(Color.white.opacity(0.2))
                .frame(width: 2, height: 16)
            
            Spacer()
        }
    }
    
    // MARK: - User Reply Section
    
    private var userReplySection: some View {
        HStack(alignment: .top, spacing: 12) {
            // User avatar
            Circle()
                .fill(Color.blue.opacity(0.3))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(thread.userReply.authorInitials)
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: 6) {
                // User name and username
                HStack(spacing: 6) {
                    Text(thread.userReply.authorName)
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .foregroundColor(.white)
                    
                    Text("@\(thread.userReply.authorUsername)")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundColor(.white.opacity(0.6))
                    
                    Spacer()
                    
                    Text(thread.userReply.timeAgo)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                // Reply content
                Text(thread.userReply.content)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundColor(.white)
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
                    .font(.custom("OpenSans-Bold", size: 11))
                    .foregroundColor(categoryColor.opacity(0.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(categoryColor.opacity(0.15))
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
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                    
                    Text("\(thread.userReply.amenCount)")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            
            // Reply count
            if thread.userReply.replyCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                    
                    Text("\(thread.userReply.replyCount)")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundColor(.white.opacity(0.6))
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
