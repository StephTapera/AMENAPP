//
//  BereanActivityAttributes.swift
//  AMENAPP
//
//  Data model for the Berean AI Dynamic Island Live Activity.
//  Shared between the main app target and the widget extension target.
//
//  When user taps the Berean sparkle button on a post, a Live Activity
//  launches showing the AI response in the Dynamic Island. On devices
//  without Dynamic Island, falls back to a bottom sheet.
//

import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

// MARK: - Berean AI Live Activity Attributes

struct BereanActivityAttributes: Codable, Hashable {
    let postID: String
    let postAuthor: String
    let postPreview: String // First 60 chars of the post

    struct ContentState: Codable, Hashable {
        var phase: BereanPhase
        var responseText: String
        var sourceCount: Int
        var scriptures: [String]
    }
}

#if canImport(ActivityKit)
extension BereanActivityAttributes: ActivityAttributes {}
#endif

// MARK: - Phase Enum

enum BereanPhase: String, Codable, Hashable {
    case loading    // "Searching scriptures..."
    case responding // Streaming response text
    case complete   // Full response ready
    case error      // Something went wrong

    var statusText: String {
        switch self {
        case .loading:    return "Searching scriptures..."
        case .responding: return "Berean is responding..."
        case .complete:   return "Response ready"
        case .error:      return "Something went wrong"
        }
    }
}
