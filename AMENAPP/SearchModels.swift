//
//  SearchModels.swift
//  AMENAPP
//
//  Created by AI Assistant on 2/5/26.
//
//  Shared models for search functionality
//

import Foundation
import SwiftUI

// MARK: - Search Filter

enum SearchFilter: String, CaseIterable {
    case all = "All"
    case people = "People"
    case groups = "Groups"
    case posts = "Posts"
    case events = "Events"
}

// MARK: - Search Result Model

struct AppSearchResult: Identifiable {
    let id = UUID()
    let firestoreId: String?  // Firebase document ID for the user/post/group
    let title: String
    let subtitle: String
    let metadata: String
    let type: ResultType
    let isVerified: Bool
    
    enum ResultType {
        case person
        case group
        case post
        case event
        
        var icon: String {
            switch self {
            case .person: return "person.circle.fill"
            case .group: return "person.3.fill"
            case .post: return "doc.text.fill"
            case .event: return "calendar.circle.fill"
            }
        }
    }
}
