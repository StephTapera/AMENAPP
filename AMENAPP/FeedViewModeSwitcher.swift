//
//  FeedViewModeSwitcher.swift
//  AMENAPP
//
//  Posts vs Photos & Videos toggle for profile feeds.
//  Liquid Glass segmented pill control.
//

import SwiftUI

enum FeedViewMode: String, CaseIterable {
    case posts = "Posts"
    case media = "Photos & Videos"

    var icon: String {
        switch self {
        case .posts: return "text.alignleft"
        case .media: return "photo.on.rectangle"
        }
    }
}

struct FeedViewModeSwitcher: View {
    @Binding var selectedMode: FeedViewMode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(FeedViewMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
                        selectedMode = mode
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 12, weight: .medium))

                        Text(mode.rawValue)
                            .font(.system(size: 13, weight: selectedMode == mode ? .semibold : .medium))
                    }
                    .foregroundColor(selectedMode == mode ? .black : .black.opacity(0.4))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Group {
                            if selectedMode == mode {
                                Capsule()
                                    .fill(Color.white)
                                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.04))
        )
    }
}
