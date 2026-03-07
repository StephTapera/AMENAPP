//
//  ConsoleLogFilter.swift
//  AMENAPP
//
//  Created to filter out noisy system logs and highlight important app logs
//

import Foundation
import os.log
import Security

// MARK: - Minimal Keychain Helper (PII storage)
//
// Used for storing PII like emailForSignIn securely in the Keychain
// rather than UserDefaults which is accessible in backups / on-device plain text.
//
enum SecureStorage {
    private static let service = "com.amen.app"

    static func save(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        // Delete existing entry first (update pattern)
        let deleteQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        // Add new entry
        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func load(account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnData: true
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Release Build Log Suppression
//
// In release builds ALL `print()` calls are completely stripped by the compiler.
// This eliminates 4,000+ print statements from the release binary, preventing
// PII/auth-token leaks through the device Console and removing measurable CPU cost.
//
// DEBUG builds behave exactly as before — print() works normally.
//
// Usage: no code changes needed anywhere else. The compiler substitutes this
// overload in non-DEBUG configurations and optimises the empty body away entirely.
#if !DEBUG
@_transparent
@inline(__always)
func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    // intentionally empty — stripped in release
}

@_transparent
@inline(__always)
func print(_ items: Any...) {
    // intentionally empty — stripped in release
}
#endif

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
