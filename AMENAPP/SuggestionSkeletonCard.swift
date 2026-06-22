// SuggestionSkeletonCard.swift
// AMENAPP
//
// Shimmer loading placeholder card for the suggestions rail.
// Extracted from SuggestedForYouModule.swift.

import SwiftUI

struct SuggestionSkeletonCard: View {
    @State private var shimmer = false

    private let cardWidth: CGFloat = 168
    private let cardHeight: CGFloat = 240

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                // Avatar
                Circle()
                    .fill(Color(.systemFill))
                    .frame(width: 48, height: 48)

                // Name
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemFill))
                    .frame(width: 95, height: 12)

                // Handle
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(.systemFill))
                    .frame(width: 65, height: 10)

                // Reason
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(.systemFill))
                    .frame(width: 110, height: 10)

                // Context row
                HStack(spacing: 4) {
                    ForEach(0..<2, id: \.self) { _ in
                        Circle().fill(Color(.systemFill)).frame(width: 14, height: 14)
                    }
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(.systemFill))
                        .frame(width: 50, height: 8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)

            Spacer()

            // Button placeholders
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemFill))
                    .frame(height: 30)
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemFill))
                    .frame(height: 30)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.75)
                )
        )
        .opacity(shimmer ? 0.50 : 1.0)
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: shimmer)
        .onAppear { shimmer = true }
    }
}
