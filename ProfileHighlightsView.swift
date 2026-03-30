//
//  ProfileHighlightsView.swift
//  AMENAPP
//
//  Curated "Top Testimonies" and "Most Amened" sections for user profiles.
//  Horizontally scrolling highlight cards above the posts tab.
//

import SwiftUI

struct ProfileHighlightsView: View {
    let posts: [Post]
    let showOnOwnProfile: Bool

    // Top posts by engagement
    private var topTestimonies: [Post] {
        posts.filter { $0.category == .testimonies }
            .sorted { $0.amenCount + $0.commentCount > $1.amenCount + $1.commentCount }
            .prefix(5)
            .map { $0 }
    }

    private var mostAmened: [Post] {
        posts.sorted { $0.amenCount > $1.amenCount }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !topTestimonies.isEmpty {
                highlightSection(title: "Top Testimonies", icon: "star.fill", posts: topTestimonies)
            }

            if !mostAmened.isEmpty && showOnOwnProfile {
                highlightSection(title: "Most Amened", icon: "hands.sparkles.fill", posts: mostAmened)
            }
        }
    }

    private func highlightSection(title: String, icon: String, posts: [Post]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(posts) { post in
                        HighlightCard(post: post)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

private struct HighlightCard: View {
    let post: Post

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(post.content)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .lineSpacing(2)

            HStack(spacing: 12) {
                Label("\(post.amenCount)", systemImage: "hands.sparkles.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Label("\(post.commentCount)", systemImage: "bubble")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 200, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        )
    }
}
