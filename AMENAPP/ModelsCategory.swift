//
//  Category.swift
//  AMENAPP
//
//  Created by Steph on 1/14/26.
//

import Foundation

struct Category: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let icon: String
    
    init(id: String = UUID().uuidString, name: String, description: String, icon: String) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
    }
}

extension Category {
    static let allCategories: [Category] = [
        Category(
            name: "Testimonies",
            description: "Share your faith journey",
            icon: "heart.fill"
        ),
        Category(
            name: "#OPENTABLE",
            description: "AI • Bible & Tech • Business • Ideas",
            icon: "bubble.left.and.bubble.right.fill"
        ),
        Category(
            name: "Prayer",
            description: "Prayer requests and support",
            icon: "hands.sparkles.fill"
        )
    ]
    
    static let openTable = allCategories[1]
}
