//
//  TrendingTopic.swift
//  AMENAPP
//
//  Created by Steph on 1/14/26.
//

import SwiftUI

struct TrendingTopic: Identifiable {
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
    static let mockTopics: [TrendingTopic] = [
        TrendingTopic(
            icon: "brain.head.profile",
            iconColor: .blue,
            title: "AI & Faith",
            backgroundColor: Color(red: 0.93, green: 0.95, blue: 1.0),
            postsCount: 142
        ),
        TrendingTopic(
            icon: "shield.checkered",
            iconColor: .green,
            title: "Tech Ethics",
            backgroundColor: Color(red: 0.92, green: 0.99, blue: 0.96),
            postsCount: 89
        ),
        TrendingTopic(
            icon: "lightbulb.fill",
            iconColor: .orange,
            title: "Startups",
            backgroundColor: Color(red: 1.0, green: 0.97, blue: 0.93),
            postsCount: 203
        ),
        TrendingTopic(
            icon: "book.fill",
            iconColor: .purple,
            title: "Scripture",
            backgroundColor: Color(red: 0.96, green: 0.94, blue: 1.0),
            postsCount: 167
        )
    ]
}
