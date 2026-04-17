// SuggestionAvatarView.swift
// AMENAPP
//
// Avatar with type-specific gradient background and verified accent ring.
// Extracted from SuggestedForYouModule.swift.

import SwiftUI

struct SuggestionAvatarView: View {
    let item: SuggestionItem
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(avatarFill)
                .frame(width: size, height: size)

            if let url = item.avatarURL.flatMap(URL.init) {
                CachedAsyncImage(url: url, size: CGSize(width: size * 2, height: size * 2)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                } placeholder: {
                    initialsView
                }
            } else {
                initialsView
            }

            // Verified accent ring
            if item.isVerified {
                Circle()
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
                    .frame(width: size + 3, height: size + 3)
            }
        }
        .frame(width: size + 3, height: size + 3)
    }

    private var initialsView: some View {
        Text(item.initials)
            .font(.system(size: size * 0.34, weight: .semibold))
            .foregroundStyle(.white)
    }

    private var avatarFill: some ShapeStyle {
        switch item.accountType {
        case .church:    return AnyShapeStyle(LinearGradient(colors: [Color(hex: "10B981"), Color(hex: "34D399")], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .creator:   return AnyShapeStyle(LinearGradient(colors: [Color(hex: "EC4899"), Color(hex: "F472B6")], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .ministry:  return AnyShapeStyle(LinearGradient(colors: [Color(hex: "6B48FF"), Color(hex: "8B5CF6")], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .business:  return AnyShapeStyle(LinearGradient(colors: [Color(hex: "F59E0B"), Color(hex: "FBBF24")], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .official:  return AnyShapeStyle(Color.black)
        case .personal:  return AnyShapeStyle(LinearGradient(colors: [Color(.systemGray3), Color(.systemGray4)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }
}
