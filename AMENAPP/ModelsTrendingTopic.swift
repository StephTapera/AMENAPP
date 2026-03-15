//
//  TrendingTopic.swift
//  AMENAPP
//
//  Created by Steph on 1/14/26.
//

import SwiftUI

struct TrendingTopic: Identifiable, Hashable {
    static func == (lhs: TrendingTopic, rhs: TrendingTopic) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    let id: String
    let icon: String
    let iconColor: Color
    let title: String
    let backgroundColor: Color
    let postsCount: Int
    
    init(
        id: String = UUID().uuidString,
        icon: String,
        iconColor: Color,
        title: String,
        backgroundColor: Color,
        postsCount: Int = 0
    ) {
        self.id = id
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.backgroundColor = backgroundColor
        self.postsCount = postsCount
    }
}

extension TrendingTopic {
    // P2: Faith-centered, AMEN-appropriate default topics.
    // backgroundColor is intentionally set to .clear here — the TrendingSection
    // renders `iconColor.opacity(0.12)` directly so it works in both light and dark mode.
    // These are replaced by live Firestore data as soon as loadTrendingFromFirestore() resolves.
    static let mockTopics: [TrendingTopic] = [
        TrendingTopic(
            icon: "book.fill",
            iconColor: .indigo,
            title: "Scripture",
            backgroundColor: .clear,
            postsCount: 248
        ),
        TrendingTopic(
            icon: "hands.sparkles",
            iconColor: .purple,
            title: "Prayer",
            backgroundColor: .clear,
            postsCount: 312
        ),
        TrendingTopic(
            icon: "star.fill",
            iconColor: .orange,
            title: "Testimony",
            backgroundColor: .clear,
            postsCount: 189
        ),
        TrendingTopic(
            icon: "heart.fill",
            iconColor: .pink,
            title: "Devotional",
            backgroundColor: .clear,
            postsCount: 156
        ),
        TrendingTopic(
            icon: "building.columns.fill",
            iconColor: .teal,
            title: "Church Life",
            backgroundColor: .clear,
            postsCount: 127
        ),
        TrendingTopic(
            icon: "person.3.fill",
            iconColor: .blue,
            title: "Community",
            backgroundColor: .clear,
            postsCount: 203
        )
    ]
}
