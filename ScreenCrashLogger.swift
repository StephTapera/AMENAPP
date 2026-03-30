/// ScreenCrashLogger.swift
/// AMENAPP
///
/// Centralized crash-diagnostic logger that captures detailed lifecycle events
/// for every major screen. Logs go to:
///   1. Console (via dlog) — visible in Xcode debug output
///   2. Firebase Crashlytics custom keys/logs — available in crash reports
///   3. Local on-device file — survives crashes, readable after restart
///
/// Usage:
///   ScreenCrashLogger.log(.homeAppeared, context: ["postCount": "\(posts.count)"])
///   ScreenCrashLogger.log(.error("MessagesView"), context: ["error": error.localizedDescription])

import Foundation
import FirebaseCrashlytics

// MARK: - Screen Event Types

enum ScreenEvent: CustomStringConvertible {
    // Tab navigation
    case tabSwitched(from: Int, to: Int)
    
    // Screen lifecycle
    case homeAppeared
    case homeDisappeared
    case discoveryAppeared
    case discoveryDisappeared
    case messagesAppeared
    case messagesDisappeared
    case resourcesAppeared
    case resourcesDisappeared
    case notificationsAppeared
    case notificationsDisappeared
    case profileAppeared
    case profileDisappeared
    
    // Data loading
    case dataLoadStarted(String)
    case dataLoadCompleted(String)
    case dataLoadFailed(String)
    
    // Errors
    case error(String)
    case fatalState(String)
    
    // View body evaluation
    case bodyEvaluated(String)
    
    // Navigation
    case sheetPresented(String)
    case sheetDismissed(String)
    case navigationPush(String)
    case navigationPop(String)
    
    var description: String {
        switch self {
        case .tabSwitched(let from, let to): return "TAB_SWITCH \(from)→\(to)"
        case .homeAppeared: return "HOME_APPEARED"
        case .homeDisappeared: return "HOME_DISAPPEARED"
        case .discoveryAppeared: return "DISCOVERY_APPEARED"
        case .discoveryDisappeared: return "DISCOVERY_DISAPPEARED"
        case .messagesAppeared: return "MESSAGES_APPEARED"
        case .messagesDisappeared: return "MESSAGES_DISAPPEARED"
        case .resourcesAppeared: return "RESOURCES_APPEARED"
        case .resourcesDisappeared: return "RESOURCES_DISAPPEARED"
        case .notificationsAppeared: return "NOTIFICATIONS_APPEARED"
        case .notificationsDisappeared: return "NOTIFICATIONS_DISAPPEARED"
        case .profileAppeared: return "PROFILE_APPEARED"
        case .profileDisappeared: return "PROFILE_DISAPPEARED"
        case .dataLoadStarted(let s): return "DATA_LOAD_START: \(s)"
        case .dataLoadCompleted(let s): return "DATA_LOAD_OK: \(s)"
        case .dataLoadFailed(let s): return "DATA_LOAD_FAIL: \(s)"
        case .error(let s): return "ERROR: \(s)"
        case .fatalState(let s): return "FATAL_STATE: \(s)"
        case .bodyEvaluated(let s): return "BODY_EVAL: \(s)"
        case .sheetPresented(let s): return "SHEET_PRESENT: \(s)"
        case .sheetDismissed(let s): return "SHEET_DISMISS: \(s)"
        case .navigationPush(let s): return "NAV_PUSH: \(s)"
        case .navigationPop(let s): return "NAV_POP: \(s)"
        }
    }
    
    /// Severity for filtering
    var severity: Severity {
        switch self {
        case .error, .dataLoadFailed: return .error
        case .fatalState: return .fatal
        default: return .info
        }
    }
    
    enum Severity: String {
        case info = "INFO"
        case error = "ERROR"
        case fatal = "FATAL"
    }
}

// MARK: - ScreenCrashLogger

final class ScreenCrashLogger: @unchecked Sendable {
    
    static let shared = ScreenCrashLogger()
    
    /// Maximum entries kept in the rolling log file
    private let maxLogEntries = 500
    
    /// In-memory ring buffer of the last N events (thread-safe via queue)
    private var recentEvents: [(Date, String)] = []
    private let queue = DispatchQueue(label: "com.amen.screenCrashLogger", qos: .utility)
    
    /// File URL for the persistent crash log (nil if document directory is unavailable)
    private let logFileURL: URL? = {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return docs.appendingPathComponent("amen_screen_crash_log.txt")
    }()
    
    private init() {
        // Load last-session log on startup so we can report it
        loadPreviousSessionLog()
    }
    
    // MARK: - Memory Monitoring
    
    /// Returns current app memory usage in MB
    static var memoryUsageMB: String {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return "?" }
        let mb = Double(info.resident_size) / (1024 * 1024)
        return String(format: "%.1f", mb)
    }
    
    /// Returns current thread count (approximate)
    static var threadCount: String {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        let result = task_threads(mach_task_self_, &threadList, &threadCount)
        if result == KERN_SUCCESS, let list = threadList {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: list), vm_size_t(Int(threadCount) * MemoryLayout<thread_act_t>.size))
        }
        return result == KERN_SUCCESS ? "\(threadCount)" : "?"
    }
    
    /// Log a periodic health snapshot (memory + threads + listener counts)
    static func logHealthSnapshot(label: String = "periodic", file: String = #file, line: Int = #line) {
        log(.bodyEvaluated("HEALTH_CHECK:\(label)"), context: [
            "memoryMB": memoryUsageMB,
            "threads": threadCount,
            "isMainThread": "\(Thread.isMainThread)"
        ], file: file, line: line)
    }
    
    // MARK: - Public API
    
    /// Log a screen event with optional key-value context.
    /// Thread-safe, non-blocking.
    static func log(
        _ event: ScreenEvent,
        context: [String: String] = [:],
        file: String = #file,
        line: Int = #line
    ) {
        shared.logEvent(event, context: context, file: file, line: line)
    }
    
    /// Convenience for logging state snapshots on screen appear
    static func logScreenState(
        _ screen: String,
        state: [String: String],
        file: String = #file,
        line: Int = #line
    ) {
        let formatted = state.map { "  \($0.key)=\($0.value)" }.joined(separator: "\n")
        let message = "[\(screen)] STATE SNAPSHOT:\n\(formatted)"
        dlog("📊 \(message)")
        
        // Set Crashlytics keys for this screen
        let crashlytics = Crashlytics.crashlytics()
        crashlytics.setCustomValue(screen, forKey: "last_screen")
        for (key, value) in state {
            crashlytics.setCustomValue(value, forKey: "\(screen.lowercased())_\(key)")
        }
        crashlytics.log(message)
        
        shared.appendToFile(message)
    }
    
    /// Get the last N log entries (for displaying in a debug view)
    static func recentLogs(count: Int = 50) -> [String] {
        var result: [String] = []
        shared.queue.sync {
            let start = max(0, shared.recentEvents.count - count)
            result = shared.recentEvents[start...].map { entry in
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm:ss.SSS"
                return "[\(formatter.string(from: entry.0))] \(entry.1)"
            }
        }
        return result
    }
    
    /// Read the full persisted log file
    static func readLogFile() -> String {
        guard let url = shared.logFileURL,
              FileManager.default.fileExists(atPath: url.path) else {
            return "(no log file)"
        }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? "(read error)"
    }

    /// Clear the log file (e.g., after successful launch)
    static func clearLogFile() {
        guard let url = shared.logFileURL else { return }
        try? "".write(to: url, atomically: true, encoding: .utf8)
    }
    
    // MARK: - Internal
    
    private func logEvent(
        _ event: ScreenEvent,
        context: [String: String],
        file: String,
        line: Int
    ) {
        let fileName = (file as NSString).lastPathComponent
        let timestamp = Date()
        let contextStr = context.isEmpty ? "" : " | " + context.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        let fullMessage = "[\(event.severity.rawValue)] \(event.description)\(contextStr) [\(fileName):\(line)]"
        
        // 1. Console output
        let emoji: String
        switch event.severity {
        case .info: emoji = "📋"
        case .error: emoji = "❌"
        case .fatal: emoji = "💀"
        }
        dlog("\(emoji) [CRASH_LOG] \(fullMessage)")
        
        // 2. Crashlytics
        let crashlytics = Crashlytics.crashlytics()
        crashlytics.log(fullMessage)
        crashlytics.setCustomValue(event.description, forKey: "last_screen_event")
        crashlytics.setCustomValue(fileName, forKey: "last_screen_event_file")
        
        // For errors, record as non-fatal
        if event.severity == .error || event.severity == .fatal {
            let userInfo: [String: Any] = [
                "event": event.description,
                "context": context.description,
                "file": fileName,
                "line": line
            ]
            crashlytics.record(error: NSError(
                domain: "com.amen.screenCrash",
                code: event.severity == .fatal ? -999 : -1,
                userInfo: userInfo
            ))
        }
        
        // 3. In-memory ring buffer
        queue.async { [weak self] in
            guard let self else { return }
            self.recentEvents.append((timestamp, fullMessage))
            if self.recentEvents.count > self.maxLogEntries {
                self.recentEvents.removeFirst(self.recentEvents.count - self.maxLogEntries)
            }
        }
        
        // 4. Persist to file (async, non-blocking)
        appendToFile(fullMessage)
    }
    
    private func appendToFile(_ message: String) {
        queue.async { [weak self] in
            guard let self else { return }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
            let line = "[\(formatter.string(from: Date()))] \(message)\n"
            
            guard let url = self.logFileURL else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                if let data = line.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            } else {
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
    
    private func loadPreviousSessionLog() {
        guard let url = logFileURL,
              FileManager.default.fileExists(atPath: url.path),
              let contents = try? String(contentsOf: url, encoding: .utf8),
              !contents.isEmpty else { return }
        
        // Send previous session's log to Crashlytics as breadcrumbs
        let lines = contents.components(separatedBy: "\n").suffix(20)
        let summary = lines.joined(separator: "\n")
        Crashlytics.crashlytics().log("=== PREVIOUS SESSION LOG (last 20) ===\n\(summary)")
        dlog("📋 [CRASH_LOG] Loaded previous session log (\(contents.count) bytes)")
    }
}

// MARK: - SwiftUI View Modifier for automatic lifecycle logging

import SwiftUI

/// Attach to any view to automatically log onAppear/onDisappear with state context.
/// Usage:  .crashLogLifecycle("HomeView") { ["postCount": "\(posts.count)"] }
struct CrashLogLifecycleModifier: ViewModifier {
    let screenName: String
    let stateProvider: () -> [String: String]
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                let state = stateProvider()
                ScreenCrashLogger.logScreenState(screenName, state: state)
            }
            .onDisappear {
                ScreenCrashLogger.log(
                    .bodyEvaluated("\(screenName) disappeared"),
                    context: ["screen": screenName]
                )
            }
    }
}

extension View {
    /// Attach crash logging to any screen view.
    /// The `state` closure is called on each appear to capture current state for diagnostics.
    func crashLogLifecycle(_ screen: String, state: @escaping () -> [String: String] = { [:] }) -> some View {
        modifier(CrashLogLifecycleModifier(screenName: screen, stateProvider: state))
    }
}
