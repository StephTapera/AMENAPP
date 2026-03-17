//
//  Logger.swift
//  AMENAPP
//
//  Production-safe logging utility
//

import Foundation

enum LogLevel: String {
    case debug = "🔍"
    case info = "ℹ️"
    case warning = "⚠️"
    case error = "❌"
    case critical = "🔥"
}

struct Logger {
    private static let isDebug: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()
    
    // MARK: - Public Methods
    
    static func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        log(message, level: .debug, file: file, function: function, line: line)
        #endif
    }
    
    static func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, file: file, function: function, line: line)
    }
    
    static func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, file: file, function: function, line: line)
    }
    
    static func error(_ message: String, error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        var fullMessage = message
        if let error = error {
            fullMessage += " - \(error.localizedDescription)"
        }
        log(fullMessage, level: .error, file: file, function: function, line: line)
    }
    
    static func critical(_ message: String, error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        var fullMessage = message
        if let error = error {
            fullMessage += " - \(error.localizedDescription)"
        }
        log(fullMessage, level: .critical, file: file, function: function, line: line)
    }
    
    // MARK: - Private Methods
    
    private static func log(_ message: String, level: LogLevel, file: String, function: String, line: Int) {
        // In release, only log warnings and above
        #if !DEBUG
        guard level == .warning || level == .error || level == .critical else { return }
        #endif
        
        let filename = (file as NSString).lastPathComponent
        let timestamp = dateFormatter.string(from: Date())
        
        #if DEBUG
        dlog("\(timestamp) \(level.rawValue) [\(filename):\(line)] \(function) - \(message)")
        #else
        // Production: simplified output
        dlog("\(level.rawValue) \(message)")
        #endif
    }
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}
