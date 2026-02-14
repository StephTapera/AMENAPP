//
//  MentionModels.swift
//  AMENAPP
//
//  Created by AI Assistant on 2/12/26.
//

import Foundation
import SwiftUI

// MARK: - Mention Models

struct Mention: Codable, Identifiable, Hashable {
    let id: String
    let userId: String
    let username: String
    let displayName: String
    let range: NSRange
    
    enum CodingKeys: String, CodingKey {
        case id, userId, username, displayName
        case rangeLocation = "range_location"
        case rangeLength = "range_length"
    }
    
    init(id: String = UUID().uuidString, userId: String, username: String, displayName: String, range: NSRange) {
        self.id = id
        self.userId = userId
        self.username = username
        self.displayName = displayName
        self.range = range
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        username = try container.decode(String.self, forKey: .username)
        displayName = try container.decode(String.self, forKey: .displayName)
        let location = try container.decode(Int.self, forKey: .rangeLocation)
        let length = try container.decode(Int.self, forKey: .rangeLength)
        range = NSRange(location: location, length: length)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(username, forKey: .username)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(range.location, forKey: .rangeLocation)
        try container.encode(range.length, forKey: .rangeLength)
    }
}

// MARK: - Mention User Search Result

struct MentionUser: Identifiable, Hashable {
    let id: String
    let userId: String
    let username: String
    let displayName: String
    let profileImageUrl: String?
    
    init(id: String = UUID().uuidString, userId: String, username: String, displayName: String, profileImageUrl: String? = nil) {
        self.id = id
        self.userId = userId
        self.username = username
        self.displayName = displayName
        self.profileImageUrl = profileImageUrl
    }
}

// MARK: - Mention Notification

struct MentionNotification: Codable {
    let id: String
    let mentionedUserId: String
    let mentioningUserId: String
    let mentioningUserName: String
    let contentType: MentionContentType
    let contentId: String
    let contentPreview: String
    let timestamp: Date
    let isRead: Bool
    
    enum MentionContentType: String, Codable {
        case post
        case comment
    }
}

// MARK: - Attributed String Extensions

extension String {
    func detectMentions() -> [NSRange] {
        var ranges: [NSRange] = []
        let pattern = "@\\w+"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return ranges
        }
        
        let nsString = self as NSString
        let matches = regex.matches(in: self, options: [], range: NSRange(location: 0, length: nsString.length))
        
        for match in matches {
            ranges.append(match.range)
        }
        
        return ranges
    }
    
    func extractMentionUsername(from range: NSRange) -> String? {
        let nsString = self as NSString
        guard range.location != NSNotFound,
              range.location + range.length <= nsString.length else {
            return nil
        }
        
        let mention = nsString.substring(with: range)
        return mention.replacingOccurrences(of: "@", with: "")
    }
}
