//
//  MessageGroupingHelper.swift
//  AMENAPP
//
//  Helper for grouping messages by sender and time
//

import Foundation

// MARK: - Message Grouping

struct MessageGroup: Identifiable {
    let id = UUID()
    let senderId: String
    let messages: [AppMessage]
    
    var showAvatar: Bool {
        // Show avatar for the last message in group (bottom)
        return true
    }
    
    var showSenderName: Bool {
        // Show sender name for the first message in group (top)
        return !messages.isEmpty && !messages[0].isFromCurrentUser
    }
}

extension Array where Element == AppMessage {
    /// Group messages by sender and time proximity
    /// - Parameter timeThreshold: Maximum seconds between messages to group them (default: 5 minutes)
    /// - Returns: Array of message groups
    func groupedMessages(timeThreshold: TimeInterval = 300) -> [MessageGroup] {
        guard !isEmpty else { return [] }
        
        var groups: [MessageGroup] = []
        var currentGroup: [AppMessage] = []
        var currentSenderId: String? = nil
        var lastTimestamp: Date? = nil
        
        for message in self {
            let shouldStartNewGroup: Bool
            
            if let lastTime = lastTimestamp,
               let currentSender = currentSenderId {
                // Check if we should start a new group
                let timeDifference = message.timestamp.timeIntervalSince(lastTime)
                let differentSender = message.senderId != currentSender
                let tooMuchTime = timeDifference > timeThreshold
                
                shouldStartNewGroup = differentSender || tooMuchTime
            } else {
                shouldStartNewGroup = true
            }
            
            if shouldStartNewGroup {
                // Save current group if it exists
                if !currentGroup.isEmpty, let senderId = currentSenderId {
                    groups.append(MessageGroup(senderId: senderId, messages: currentGroup))
                }
                
                // Start new group
                currentGroup = [message]
                currentSenderId = message.senderId
            } else {
                // Add to current group
                currentGroup.append(message)
            }
            
            lastTimestamp = message.timestamp
        }
        
        // Don't forget the last group
        if !currentGroup.isEmpty, let senderId = currentSenderId {
            groups.append(MessageGroup(senderId: senderId, messages: currentGroup))
        }
        
        return groups
    }
}

// MARK: - Timestamp Formatting

extension Date {
    /// Format timestamp for message display
    /// - Returns: Formatted string like "12:30 PM", "Yesterday", "Jan 24"
    func messageTimestamp() -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(self) {
            // Today: Show time
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: self)
        } else if calendar.isDateInYesterday(self) {
            // Yesterday
            return "Yesterday"
        } else if calendar.isDate(self, equalTo: now, toGranularity: .weekOfYear) {
            // This week: Show day name
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE" // Monday, Tuesday, etc.
            return formatter.string(from: self)
        } else if calendar.isDate(self, equalTo: now, toGranularity: .year) {
            // This year: Show month and day
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d" // Jan 24
            return formatter.string(from: self)
        } else {
            // Different year: Show full date
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy" // Jan 24, 2025
            return formatter.string(from: self)
        }
    }
    
    /// Check if enough time has passed to show a timestamp separator
    /// - Parameter other: The other date to compare
    /// - Parameter threshold: Time threshold in seconds (default: 15 minutes)
    /// - Returns: True if a timestamp separator should be shown
    func shouldShowTimestampSeparator(from other: Date, threshold: TimeInterval = 900) -> Bool {
        return self.timeIntervalSince(other) > threshold
    }
}

// MARK: - Message Display Helpers

extension AppMessage {
    /// Check if this message should show a timestamp above it
    /// - Parameter previousMessage: The message before this one
    /// - Returns: True if timestamp should be displayed
    func shouldShowTimestamp(after previousMessage: AppMessage?) -> Bool {
        guard let previous = previousMessage else {
            // First message always shows timestamp
            return true
        }
        
        // Show timestamp if enough time has passed (15 minutes default)
        return timestamp.shouldShowTimestampSeparator(from: previous.timestamp)
    }
    
    /// Check if this message should show the sender's avatar
    /// - Parameter nextMessage: The message after this one
    /// - Returns: True if avatar should be displayed
    func shouldShowAvatar(before nextMessage: AppMessage?) -> Bool {
        guard let next = nextMessage else {
            // Last message always shows avatar
            return true
        }
        
        // Show avatar if next message is from different sender or significant time gap
        return next.senderId != self.senderId || 
               next.timestamp.timeIntervalSince(self.timestamp) > 300 // 5 minutes
    }
    
    /// Check if this message should show the sender's name (for group chats)
    /// - Parameter previousMessage: The message before this one
    /// - Returns: True if sender name should be displayed
    func shouldShowSenderName(after previousMessage: AppMessage?) -> Bool {
        // Never show for current user's messages
        guard !isFromCurrentUser else { return false }
        
        guard let previous = previousMessage else {
            // First message always shows name
            return true
        }
        
        // Show name if previous message was from different sender or significant time gap
        return previous.senderId != self.senderId || 
               timestamp.timeIntervalSince(previous.timestamp) > 300 // 5 minutes
    }
}
