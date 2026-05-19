// AmenVisibility.swift
// AMENAPP
// Universal visibility tiers for content nodes.

import Foundation

enum AmenVisibility: String, Codable, CaseIterable, Identifiable {
    case `public`
    case followers
    case group
    case church
    case `private`

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .public: return "Public"
        case .followers: return "Followers"
        case .group: return "Group"
        case .church: return "Church"
        case .private: return "Private"
        }
    }
}
