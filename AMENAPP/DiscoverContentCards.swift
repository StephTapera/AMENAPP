//
//  DiscoverContentCards.swift
//  AMENAPP
//
//  News and Video cards for Discover feed
//

import SwiftUI

// MARK: - Discover News Card

struct DiscoverNewsCard: View {
    let item: NewsItem
    
    @State private var appeared = false
    @State private var isPressed = false
    
    var body: some View {
        Button {
            HapticManager.impact(style: .light)
            // News card tap action (could open article if URL available)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Thumbnail
                if let imageURLString = item.imageURL,
                   let imageURL = URL(string: imageURLString) {
                    CachedAsyncImage(url: imageURL) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Rectangle()
                            .fill(Color(.systemGray6))
                    }
                    .frame(height: 180)
                    .clipped()
                } else {
                    // Placeholder with category icon
                    ZStack {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(.systemGray5),
                                        Color(.systemGray6)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        Image(systemName: "newspaper")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary.opacity(0.3))
                    }
                    .frame(height: 180)
                }
                
                // Content
                VStack(alignment: .leading, spacing: 10) {
                    // Category badge
                    HStack(spacing: 6) {
                        Circle()
                            .fill(categoryColor)
                            .frame(width: 6, height: 6)
                        
                        Text(item.category.uppercased())
                            .font(.systemScaled(10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tracking(0.8)
                    }
                    
                    // Headline
                    Text(item.headline)
                        .font(.systemScaled(16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    // Metadata
                    HStack(spacing: 8) {
                        Text(item.sourceName)
                            .font(.systemScaled(12, weight: .medium))
                            .foregroundStyle(.secondary)
                        
                        Circle()
                            .fill(.secondary.opacity(0.5))
                            .frame(width: 3, height: 3)
                        
                        Text(timeAgo)
                            .font(.systemScaled(12))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
            }
        }
        .buttonStyle(.plain)
        .background(Color(.secondarySystemBackground).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.04), radius: 8, y: 4)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7)), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 15)
        .onAppear {
            withAnimation(Motion.adaptive(.spring(response: 0.5, dampingFraction: 0.76)).delay(0.1)) {
                appeared = true
            }
        }
    }
    
    private var categoryColor: Color {
        switch item.category.lowercased() {
        case "faith": return .purple
        case "church": return .blue
        case "global": return .green
        case "ministry": return .orange
        case "culture": return .pink
        default: return .gray
        }
    }
    
    private var timeAgo: String {
        let now = Date()
        let interval = now.timeIntervalSince(item.publishedAt)
        
        let hours = Int(interval / 3600)
        if hours < 1 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if hours < 24 {
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}

// MARK: - Discover Video Card

struct DiscoverVideoCard: View {
    let video: YoutubeVideoItem
    
    @State private var appeared = false
    @State private var isPressed = false
    
    var body: some View {
        Button {
            HapticManager.impact(style: .medium)
            // Video card tap action
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Thumbnail with play overlay
                ZStack(alignment: .bottomTrailing) {
                    if let thumbnailURLString = video.thumbnailURL,
                       let thumbnailURL = URL(string: thumbnailURLString) {
                        CachedAsyncImage(url: thumbnailURL) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            Rectangle()
                                .fill(Color(.systemGray6))
                        }
                        .frame(height: 200)
                        .clipped()
                    } else {
                        // Placeholder with video icon
                        ZStack {
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(.systemGray5),
                                            Color(.systemGray6)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            
                            Image(systemName: "play.rectangle.fill")
                                .font(.system(size: 56))
                                .foregroundStyle(.secondary.opacity(0.25))
                        }
                        .frame(height: 200)
                    }
                    
                    // Play button overlay
                    ZStack {
                        Circle()
                            .fill(.black.opacity(0.6))
                            .frame(width: 56, height: 56)
                        
                        Image(systemName: "play.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                            .offset(x: 2) // Visual centering
                    }
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
                    .offset(x: -16, y: -16)
                    
                    // Duration badge
                    if !video.duration.isEmpty {
                        Text(video.duration)
                            .font(.systemScaled(11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(.black.opacity(0.75))
                            )
                            .padding(12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
                .frame(height: 200)
                
                // Video info
                VStack(alignment: .leading, spacing: 10) {
                    // Title
                    Text(video.title)
                        .font(.systemScaled(15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    // Creator info
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(.systemGray5))
                            .frame(width: 24, height: 24)
                            .overlay(
                                Text(String(video.channelName.prefix(1)))
                                    .font(.systemScaled(11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            )
                        
                        Text(video.channelName)
                            .font(.systemScaled(13, weight: .medium))
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        // View count
                        HStack(spacing: 4) {
                            Image(systemName: "eye")
                                .font(.systemScaled(11))
                            Text(video.viewCount)
                                .font(.systemScaled(12))
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
            }
        }
        .buttonStyle(.plain)
        .background(Color(.secondarySystemBackground).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.04), radius: 8, y: 4)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7)), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 15)
        .onAppear {
            withAnimation(Motion.adaptive(.spring(response: 0.5, dampingFraction: 0.76)).delay(0.1)) {
                appeared = true
            }
        }
    }
}
