//
//  Date+Extensions.swift
//  AMENAPP
//
//  Created by Steph on 1/21/26.
//

import Foundation

// COMMENTED OUT TO TEST FOR DUPLICATE DECLARATION
// Uncomment this file once the duplicate is found and removed

/*
extension Date {
    /// Converts date to "time ago" format (e.g., "2h ago", "3d ago")
    /// This is the standard method name used throughout the app
    func timeAgoDisplay() -> String {
        let now = Date()
        let seconds = Int(now.timeIntervalSince(self))
        
        if seconds < 60 {
            return "Just now"
        }
        
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m ago"
        }
        
        let hours = minutes / 60
        if hours < 24 {
            return "\(hours)h ago"
        }
        
        let days = hours / 24
        if days < 7 {
            return "\(days)d ago"
        }
        
        let weeks = days / 7
        if weeks < 4 {
            return "\(weeks)w ago"
        }
        
        let months = days / 30
        if months < 12 {
            return "\(months)mo ago"
        }
        
        let years = days / 365
        return "\(years)y ago"
    }
    
    /// Alternative name for timeAgoDisplay()
    func relativeTimeString() -> String {
        return timeAgoDisplay()
    }
    
    /// Formats date as a readable string (e.g., "Jan 15, 2026")
    func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }
    
    /// Formats date with time (e.g., "Jan 15, 2026 at 3:45 PM")
    func formattedDateTime() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
}
*/

