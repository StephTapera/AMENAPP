//
//  BereanActivityAttributes.swift
//  AMENAPP
//
//  Data model for the Berean AI Dynamic Island Live Activity.
//  Shared between the main app target and the widget extension target.
//

import Foundation
import ActivityKit

struct BereanActivityAttributes: ActivityAttributes {
    let postID: String
    let postAuthor: String
    let postPreview: String

    struct ContentState: Codable, Hashable {
        var phase: BereanPhase
        var responseText: String
        var sourceCount: Int
        var scriptures: [String]
    }
}

enum BereanPhase: String, Codable, Hashable {
    case loading
    case responding
    case complete
    case error

    var statusText: String {
        switch self {
        case .loading:    return "Searching scriptures..."
        case .responding: return "Berean is responding..."
        case .complete:   return "Response ready"
        case .error:      return "Something went wrong"
        }
    }
}
