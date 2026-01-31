//
//  MessageValidator.swift
//  AMENAPP
//
//  Input validation for messaging system
//

import Foundation
import UIKit

enum ValidationError: Error, LocalizedError {
    case empty
    case tooLong(Int)
    case profanity
    case spam
    case tooManyImages(Int)
    case invalidCharacters
    
    var errorDescription: String? {
        switch self {
        case .empty:
            return "Message cannot be empty"
        case .tooLong(let max):
            return "Message is too long (max \(max) characters)"
        case .profanity:
            return "Message contains inappropriate content"
        case .spam:
            return "You're sending messages too quickly"
        case .tooManyImages(let max):
            return "Too many images (max \(max))"
        case .invalidCharacters:
            return "Message contains invalid characters"
        }
    }
}

struct MessageValidator {
    static let maxLength = 10000
    static let maxImages = 10
    static let minSearchLength = 2
    static let maxGroupNameLength = 50
    
    // MARK: - Message Text Validation
    
    static func validate(_ text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            throw ValidationError.empty
        }
        
        guard trimmed.count <= maxLength else {
            throw ValidationError.tooLong(maxLength)
        }
        
        // Check for obvious spam patterns
        if containsSpamPatterns(trimmed) {
            throw ValidationError.spam
        }
        
        // Add more validation as needed
    }
    
    // MARK: - Image Validation
    
    static func validateImages(_ images: [UIImage]) throws {
        guard images.count <= maxImages else {
            throw ValidationError.tooManyImages(maxImages)
        }
        
        // Validate each image
        for image in images {
            guard image.size.width > 0 && image.size.height > 0 else {
                throw ValidationError.invalidCharacters
            }
        }
    }
    
    // MARK: - Username/Group Name Validation
    
    static func validateUsername(_ username: String) throws {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            throw ValidationError.empty
        }
        
        guard trimmed.count <= 100 else {
            throw ValidationError.tooLong(100)
        }
    }
    
    static func validateGroupName(_ name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            throw ValidationError.empty
        }
        
        guard trimmed.count <= maxGroupNameLength else {
            throw ValidationError.tooLong(maxGroupNameLength)
        }
    }
    
    // MARK: - Search Validation
    
    static func validateSearchQuery(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= minSearchLength
    }
    
    // MARK: - Spam Detection
    
    private static func containsSpamPatterns(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        
        // Check for excessive repetition
        if hasExcessiveRepetition(text) {
            return true
        }
        
        // Check for excessive URLs
        if hasExcessiveURLs(text) {
            return true
        }
        
        return false
    }
    
    private static func hasExcessiveRepetition(_ text: String) -> Bool {
        // Check if same character repeated more than 10 times
        let pattern = "(.)\\1{9,}"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(text.startIndex..., in: text)
            return regex.firstMatch(in: text, range: range) != nil
        }
        return false
    }
    
    private static func hasExcessiveURLs(_ text: String) -> Bool {
        // Count URLs in text
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, range: NSRange(text.startIndex..., in: text))
        
        // More than 3 URLs is suspicious
        return (matches?.count ?? 0) > 3
    }
    
    // MARK: - Profanity Filter (Basic)
    
    private static let profanityList: [String] = [
        // Add profanity words here as needed
        // This is a basic example - use a comprehensive library in production
    ]
    
    static func containsProfanity(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return profanityList.contains { profanityWord in
            lowercased.contains(profanityWord)
        }
    }
}

// MARK: - Rate Limiting

class MessageRateLimiter {
    static let shared = MessageRateLimiter()
    
    private var lastMessageTime: Date?
    private var messageCount: Int = 0
    private var windowStart: Date = Date()
    
    private let minInterval: TimeInterval = 1.0 // 1 second between messages
    private let maxMessagesPerMinute = 20
    
    private init() {}
    
    func canSendMessage() -> Bool {
        let now = Date()
        
        // Check minimum interval
        if let lastTime = lastMessageTime {
            if now.timeIntervalSince(lastTime) < minInterval {
                return false
            }
        }
        
        // Check rate limit per minute
        if now.timeIntervalSince(windowStart) > 60 {
            // Reset window
            windowStart = now
            messageCount = 0
        }
        
        if messageCount >= maxMessagesPerMinute {
            return false
        }
        
        return true
    }
    
    func recordMessage() {
        lastMessageTime = Date()
        messageCount += 1
    }
    
    func reset() {
        lastMessageTime = nil
        messageCount = 0
        windowStart = Date()
    }
}
