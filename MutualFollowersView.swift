// MutualFollowersView.swift
// AMENAPP
//
// Instagram-style inline "Followed by name1, name2 and N others" row with
// overlapping avatar stack. Shown below follower/following stats in UserProfileView.
// Uses the existing MutualConnection model — no new fetch needed, data comes from mutualsVM.

import SwiftUI

// MARK: - Main Component

struct MutualFollowersView: View {
    let mutuals: [MutualConnection]

    private var visibleMutuals: [MutualConnection] { Array(mutuals.prefix(3)) }

    private var labelText: AttributedString {
        guard !mutuals.isEmpty else { return AttributedString() }

        var result = AttributedString("Followed by ")
        result.foregroundColor = Color(.secondaryLabel)
        result.font = .system(size: 12.5)

        var name1 = AttributedString(mutuals[0].username)
        name1.font = .system(size: 12.5, weight: .semibold)
        name1.foregroundColor = Color(.label)
        result += name1

        if mutuals.count == 1 { return result }

        if mutuals.count == 2 {
            var sep = AttributedString(" and ")
            sep.foregroundColor = Color(.secondaryLabel)
            sep.font = .system(size: 12.5)
            result += sep

            var name2 = AttributedString(mutuals[1].username)
            name2.font = .system(size: 12.5, weight: .semibold)
            name2.foregroundColor = Color(.label)
            result += name2
            return result
        }

        // 3+ mutuals
        var comma = AttributedString(", ")
        comma.foregroundColor = Color(.secondaryLabel)
        comma.font = .system(size: 12.5)
        result += comma

        var name2 = AttributedString(mutuals[1].username)
        name2.font = .system(size: 12.5, weight: .semibold)
        name2.foregroundColor = Color(.label)
        result += name2

        let othersCount = mutuals.count - 2
        var and = AttributedString(" and ")
        and.foregroundColor = Color(.secondaryLabel)
        and.font = .system(size: 12.5)
        result += and

        var othersNum = AttributedString("\(othersCount) other\(othersCount == 1 ? "" : "s")")
        othersNum.font = .system(size: 12.5, weight: .semibold)
        othersNum.foregroundColor = Color(.label)
        result += othersNum

        return result
    }

    @State private var appeared = false

    var body: some View {
        if mutuals.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 10) {
                MutualAvatarStack(mutuals: visibleMutuals)
                Text(labelText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 6)
            .onAppear {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.78).delay(0.1)) {
                    appeared = true
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

// MARK: - Avatar Stack

struct MutualAvatarStack: View {
    let mutuals: [MutualConnection]
    private let size: CGFloat = 28
    private let overlap: CGFloat = 10

    var totalWidth: CGFloat {
        size + CGFloat(max(mutuals.count - 1, 0)) * (size - overlap)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(mutuals.enumerated()), id: \.element.id) { index, mutual in
                MutualSingleAvatar(url: mutual.profilePhotoURL, initials: mutual.initials, size: size)
                    .offset(x: CGFloat(index) * (size - overlap))
                    .zIndex(Double(mutuals.count - index))
            }
        }
        .frame(width: totalWidth, height: size)
        .fixedSize()
    }
}

// MARK: - Single Avatar

struct MutualSingleAvatar: View {
    let url: URL?
    let initials: String
    let size: CGFloat

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                Circle()
                    .fill(Color(.systemGray4))
                    .overlay(
                        Text(String(initials.prefix(1)))
                            .font(.system(size: size * 0.38, weight: .semibold))
                            .foregroundStyle(Color(.secondaryLabel))
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 2))
    }
}
