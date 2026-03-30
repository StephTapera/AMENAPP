//
//  PostComment.swift
//  AMENAPP
//
//  Created by Migration Team on 1/24/26.
//
//  Model for post comments in Realtime Database
//

import Foundation

/// Comment model for posts (distinct from prayer comments, etc.)
struct PostComment: Identifiable, Codable {
    let id: UUID
    let postId: UUID
    let content: String
    let authorId: String
    let authorName: String
    let authorInitials: String
    let authorProfileImageURL: String?
    let createdAt: Date
    var amenCount: Int
    var replyCount: Int
    
    init(
        id: UUID = UUID(),
        postId: UUID,
        content: String,
        authorId: String,
        authorName: String,
        authorInitials: String,
        authorProfileImageURL: String?,
        createdAt: Date = Date(),
        amenCount: Int = 0,
        replyCount: Int = 0
    ) {
        self.id = id
        self.postId = postId
        self.content = content
        self.authorId = authorId
        self.authorName = authorName
        self.authorInitials = authorInitials
        self.authorProfileImageURL = authorProfileImageURL
        self.createdAt = createdAt
        self.amenCount = amenCount
        self.replyCount = replyCount
    }
}

// MARK: - Date Extension for Time Ago Display

extension Date {
    func timeAgoDisplay() -> String {
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.minute, .hour, .day, .weekOfYear, .month, .year], from: self, to: now)
        
        if let year = components.year, year > 0 {
            return "\(year)y"
        }
        if let month = components.month, month > 0 {
            return "\(month)mo"
        }
        if let week = components.weekOfYear, week > 0 {
            return "\(week)w"
        }
        if let day = components.day, day > 0 {
            return "\(day)d"
        }
        if let hour = components.hour, hour > 0 {
            return "\(hour)h"
        }
        if let minute = components.minute, minute > 0 {
            return "\(minute)m"
        }
        return "now"
    }
}
