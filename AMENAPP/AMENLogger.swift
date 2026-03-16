//
//  AMENLogger.swift
//  AMENAPP
//
//  Lightweight logging wrapper with log levels and PII redaction.
//  Replaces raw print() statements for production-safe logging.
//
//  Usage:
//    AMENLog.info("User signed in", category: .auth)
//    AMENLog.debug("Post loaded: \(postId)", category: .feed)
//    AMENLog.error("Failed to save: \(error)", category: .data)
//    AMENLog.warning("Rate limit approaching", category: .api)
//

import Foundation
import os.log

// MARK: - Log Level

enum AMENLogLevel: Int, Comparable {
    case debug = 0    // Verbose development info
    case info = 1     // Normal operational events
    case warning = 2  // Something unexpected but recoverable
    case error = 3    // Failures that need attention
    case critical = 4 // App-breaking issues

    static func < (lhs: AMENLogLevel, rhs: AMENLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var emoji: String {
        switch self {
        case .debug:    return "🔍"
        case .info:     return "ℹ️"
        case .warning:  return "⚠️"
        case .error:    return "❌"
        case .critical: return "🔴"
        }
    }

    var osLogType: OSLogType {
        switch self {
        case .debug:    return .debug
        case .info:     return .info
        case .warning:  return .default
        case .error:    return .error
        case .critical: return .fault
        }
    }
}

// MARK: - Log Category

enum AMENLogCategory: String {
    case auth = "Auth"
    case feed = "Feed"
    case data = "Data"
    case api = "API"
    case ai = "AI"
    case chat = "Chat"
    case notifications = "Notifications"
    case safety = "Safety"
    case translation = "Translation"
    case media = "Media"
    case performance = "Perf"
    case general = "General"

    var osLog: OSLog {
        OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.amenapp", category: rawValue)
    }
}

// MARK: - Logger

enum AMENLog {

    /// Minimum log level. Set to .warning or .error in production.
    #if DEBUG
    static var minimumLevel: AMENLogLevel = .debug
    #else
    static var minimumLevel: AMENLogLevel = .warning
    #endif

    static func debug(_ message: String, category: AMENLogCategory = .general) {
        log(message, level: .debug, category: category)
    }

    static func info(_ message: String, category: AMENLogCategory = .general) {
        log(message, level: .info, category: category)
    }

    static func warning(_ message: String, category: AMENLogCategory = .general) {
        log(message, level: .warning, category: category)
    }

    static func error(_ message: String, category: AMENLogCategory = .general) {
        log(message, level: .error, category: category)
    }

    static func critical(_ message: String, category: AMENLogCategory = .general) {
        log(message, level: .critical, category: category)
    }

    // MARK: - PII Redaction

    /// Redact sensitive data for logs. Returns full value in DEBUG, redacted in RELEASE.
    static func redact(_ value: String) -> String {
        #if DEBUG
        return value
        #else
        guard value.count > 4 else { return "***" }
        return String(value.prefix(2)) + "***" + String(value.suffix(2))
        #endif
    }

    /// Redact a user ID (show first 4 chars only in production).
    static func redactUID(_ uid: String) -> String {
        #if DEBUG
        return uid
        #else
        return String(uid.prefix(4)) + "***"
        #endif
    }

    // MARK: - Private

    private static func log(_ message: String, level: AMENLogLevel, category: AMENLogCategory) {
        guard level >= minimumLevel else { return }

        let formatted = "\(level.emoji) [\(category.rawValue)] \(message)"

        // Use os_log for structured logging (visible in Console.app)
        os_log("%{public}@", log: category.osLog, type: level.osLogType, formatted)

        // Also print in DEBUG for Xcode console
        #if DEBUG
        print(formatted)
        #endif
    }
}
