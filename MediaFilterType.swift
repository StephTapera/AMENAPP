// MediaFilterType.swift — filter/source enums for ChristianMediaView

import Foundation
import SwiftUI

enum MediaFilterType: String, CaseIterable, Identifiable, Codable, Hashable {
    case all, sermons, podcasts, worship, devotionals
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "All"
        case .sermons: return "Sermons"
        case .podcasts: return "Podcasts"
        case .worship: return "Worship"
        case .devotionals: return "Devotionals"
        }
    }
    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .sermons: return "video.fill"
        case .podcasts: return "headphones"
        case .worship: return "music.note"
        case .devotionals: return "book.fill"
        }
    }
}

enum MediaSource: String, Codable, Hashable {
    case youtube, rss, spotify
}

enum MediaTab: String, CaseIterable, Identifiable {
    case forYou = "For You"
    case discover = "Discover"
    case library = "Library"
    var id: String { rawValue }
}
