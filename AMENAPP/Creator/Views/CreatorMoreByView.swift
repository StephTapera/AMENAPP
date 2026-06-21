// CreatorMoreByView.swift
// AMENAPP — Creator Spotlight / Wave 1
//
// "More by this creator" horizontal scroll of opaque white content cards.
// Finite list: max 8 items. No infinite scroll. Hidden when empty.

import SwiftUI

struct CreatorMoreByView: View {

    let contentIds: [String]

    private var displayIds: [String] {
        Array(contentIds.prefix(8))
    }

    var body: some View {
        if !displayIds.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("More by This Creator")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(displayIds, id: \.self) { contentId in
                            MoreByCard(contentId: contentId)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
                }
            }
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
        }
    }
}

// MARK: - Content Card

private struct MoreByCard: View {

    let contentId: String

    /// In production this would be driven by a loaded CreatorContent model.
    /// The card is intentionally a placeholder until the Firestore fetch is wired.

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Thumbnail placeholder
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemBackground))
                .frame(width: 140, height: 82)
                .overlay(
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 22))
                        .foregroundStyle(Color(.tertiaryLabel))
                )

            // Title placeholder line
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.secondarySystemBackground))
                .frame(height: 12)

            // Format chip placeholder
            HStack(spacing: 5) {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("Content")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.secondarySystemBackground), in: Capsule())
        }
        .padding(12)
        .frame(width: 164)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
        )
    }
}
