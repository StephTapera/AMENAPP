//
//  ConsoleLogFilter.swift
//  AMENAPP
//
//  Created to filter out noisy system logs and highlight important app logs
//

import Foundation
import os.log

/// Custom logging utility that filters out system noise and highlights app logs
struct AppLogger {
    
    // MARK: - Log Categories
    
    enum Category: String {
        case save = "💾 SAVE"
        case comment = "💬 COMMENT"
        case repost = "🔁 REPOST"
        case lightbulb = "💡 LIGHTBULB"
        case amen = "🙏 AMEN"
        case reaction = "⚡️ REACTION"
        case user = "👤 USER"
        case network = "🌐 NETWORK"
        case database = "🔥 DATABASE"
        case error = "❌ ERROR"
        case success = "✅ SUCCESS"
        case warning = "⚠️ WARNING"
        case debug = "🔍 DEBUG"
    }
    
    // MARK: - Logging Methods
    
    /// Log a message with category prefix
    static func log(_ message: String, category: Category = .debug) {
        print("[\(category.rawValue)] \(message)")
    }
    
    /// Log a save button action
    static func logSave(_ message: String, postId: String? = nil) {
        if let postId = postId {
            print("[\(Category.save.rawValue)] [\(postId.prefix(8))] \(message)")
        } else {
            print("[\(Category.save.rawValue)] \(message)")
        }
    }
    
    /// Log a comment action
    static func logComment(_ message: String, postId: String? = nil) {
        if let postId = postId {
            print("[\(Category.comment.rawValue)] [\(postId.prefix(8))] \(message)")
        } else {
            print("[\(Category.comment.rawValue)] \(message)")
        }
    }
    
    /// Log a repost action
    static func logRepost(_ message: String, postId: String? = nil) {
        if let postId = postId {
            print("[\(Category.repost.rawValue)] [\(postId.prefix(8))] \(message)")
        } else {
            print("[\(Category.repost.rawValue)] \(message)")
        }
    }
    
    /// Log a lightbulb action
    static func logLightbulb(_ message: String, postId: String? = nil) {
        if let postId = postId {
            print("[\(Category.lightbulb.rawValue)] [\(postId.prefix(8))] \(message)")
        } else {
            print("[\(Category.lightbulb.rawValue)] \(message)")
        }
    }
    
    /// Log an amen action
    static func logAmen(_ message: String, postId: String? = nil) {
        if let postId = postId {
            print("[\(Category.amen.rawValue)] [\(postId.prefix(8))] \(message)")
        } else {
            print("[\(Category.amen.rawValue)] \(message)")
        }
    }
    
    /// Log a generic reaction
    static func logReaction(_ message: String, postId: String? = nil) {
        if let postId = postId {
            print("[\(Category.reaction.rawValue)] [\(postId.prefix(8))] \(message)")
        } else {
            print("[\(Category.reaction.rawValue)] \(message)")
        }
    }
    
    /// Log an error with optional context
    static func logError(_ message: String, error: Error? = nil, file: String = #file, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        if let error = error {
            print("[\(Category.error.rawValue)] [\(fileName):\(line)] \(message) - \(error.localizedDescription)")
        } else {
            print("[\(Category.error.rawValue)] [\(fileName):\(line)] \(message)")
        }
    }
    
    /// Log a success message
    static func logSuccess(_ message: String) {
        print("[\(Category.success.rawValue)] \(message)")
    }
    
    /// Log a warning
    static func logWarning(_ message: String) {
        print("[\(Category.warning.rawValue)] \(message)")
    }
    
    // MARK: - Separator
    
    /// Print a visual separator for important sections
    static func separator() {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
    
    /// Print a section header
    static func section(_ title: String) {
        separator()
        print("  \(title)")
        separator()
    }
}
