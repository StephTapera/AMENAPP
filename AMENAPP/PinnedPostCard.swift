//
//  PinnedPostCard.swift
//  AMENAPP
//
//  Liquid glass card wrapping the existing PostCard,
//  with a left white accent stripe and a PinBadge overlay.
//

import SwiftUI
import Combine

struct PinnedPostCard: View {
    let post: Post

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 0) {
                // Left white accent stripe
                Rectangle()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 3)

                // Wrapped PostCard
                PostCard(post: post, isUserPost: false)
                    .frame(maxWidth: .infinity)
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            // Pin badge — top-right
            PinBadge()
                .padding(.top, 10)
                .padding(.trailing, 12)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}
