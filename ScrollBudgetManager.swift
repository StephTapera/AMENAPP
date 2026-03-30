//
//  ScrollBudgetManager.swift
//  AMENAPP
//
//  Scroll Budget + Reflection-Based Usage Limits
//  In-app wellbeing controls without UI design changes
//

import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth

/// Manages user-configurable daily scroll budgets for feed time with supportive nudges
class ScrollBudgetManager: ObservableObject {
    static let shared = ScrollBudgetManager()
    
    // MARK: - Published State
    
    @Published var isEnabled: Bool = false
    @Published var dailyBudgetMinutes: Int = 30 // User-configurable: 15, 30, 45, 60
    @Published var enforcementMode: EnforcementMode = .softStop
    @Published var exemptSections: Set<ExemptSection> = [.bible, .churchNotes, .messages]
    
    @Published var todayScrollMinutes: Double = 0
    @Published var currentThreshold: UsageThreshold = .none
    @Published var isLocked: Bool = false
    @Published var softStopExtensionsUsed: Int = 0
    
    // MARK: - Budget State
    
    private var sessionStartTime: Date?
    private var activeScrollStartTime: Date?
    private var todayDate: String = ""
    private var compulsiveReopenCount: Int = 0
    private var lastAppCloseTime: Date?
    
    private var cancellables = Set<AnyCancellable>()
    private let db = Firestore.firestore()
    
    // MARK: - Configuration Types
    
    enum EnforcementMode: String, CaseIterable, Codable {
        case softStop = "Soft Stop (2 extensions)"
        case hardStop = "Hard Stop (no extensions)"
        
        var maxExtensions: Int {
            switch self {
            case .softStop: return 2
            case .hardStop: return 0
            }
        }
    }
    
    enum ExemptSection: String, CaseIterable, Codable {
        case bible = "Bible Study"
        case churchNotes = "Church Notes"
        case messages = "Messages"
        case prayer = "Prayer Requests"
        
        var tabIndex: Int? {
            switch self {
            case .bible: return nil // Resources tab subsection
            case .churchNotes: return nil // Resources tab subsection
            case .messages: return 5
            case .prayer: return 2
            }
        }
    }
    
    enum UsageThreshold: String {
        case none = "none"
        case fifty = "50% used"
        case eighty = "80% used"
        case full = "100% used (budget reached)"
    }
    
    // MARK: - Supportive Redirect Options
    
    enum RedirectOption: CaseIterable {
        case prayer
        case privateNote
        case psalm
        case churchNotes
        case quietMode
        
        var title: String {
            switch self {
            case .prayer: return "Write a Prayer"
            case .privateNote: return "Save Your Thoughts"
            case .psalm: return "Read a Psalm"
            case .churchNotes: return "Review Church Notes"
            case .quietMode: return "Enter Quiet Mode"
            }
        }
        
        var subtitle: String {
            switch self {
            case .prayer: return "Share what's on your heart"
            case .privateNote: return "Reflect on what you're feeling"
            case .psalm: return "Find peace in Scripture"
            case .churchNotes: return "Revisit recent teachings"
            case .quietMode: return "Take a mindful break"
            }
        }
        
        var icon: String {
            switch self {
            case .prayer: return "hands.sparkles"
            case .privateNote: return "note.text"
            case .psalm: return "book.closed"
            case .churchNotes: return "note.text"
            case .quietMode: return "moon.stars"
            }
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        setupDailyReset()
        loadUserSettings()
        startDailyResetTimer()
    }
    
    // MARK: - Active Scroll Tracking
    
    /// Start tracking active feed scrolling (only count active scrolling, not idle time)
    func startScrollSession(inSection section: String) {
        // Check if section is exempt
        if isExemptSection(section) {
            return
        }
        
        guard isEnabled else { return }
        
        // Record start time
        activeScrollStartTime = Date()
    }
    
    /// End tracking active feed scrolling
    func endScrollSession() {
        guard isEnabled,
              let startTime = activeScrollStartTime else {
            return
        }
        
        // Calculate elapsed time in minutes
        let elapsed = Date().timeIntervalSince(startTime) / 60.0
        
        // Only count sessions longer than 3 seconds (filter out accidental taps)
        if elapsed > 0.05 {
            todayScrollMinutes += elapsed
            updateThreshold()
            saveUsageData()
        }
        
        activeScrollStartTime = nil
    }
    
    /// Check if a section is exempt from tracking
    private func isExemptSection(_ section: String) -> Bool {
        let lowerSection = section.lowercased()
        
        if exemptSections.contains(.bible) && (lowerSection.contains("bible") || lowerSection.contains("berean")) {
            return true
        }
        if exemptSections.contains(.churchNotes) && lowerSection.contains("church") {
            return true
        }
        if exemptSections.contains(.messages) && lowerSection.contains("message") {
            return true
        }
        if exemptSections.contains(.prayer) && lowerSection.contains("prayer") {
            return true
        }
        
        return false
    }
    
    // MARK: - Threshold Management
    
    private func updateThreshold() {
        let percentage = (todayScrollMinutes / Double(dailyBudgetMinutes)) * 100
        
        if percentage >= 100 {
            if currentThreshold != .full {
                currentThreshold = .full
                handleBudgetReached()
            }
        } else if percentage >= 80 {
            if currentThreshold != .eighty && currentThreshold != .full {
                currentThreshold = .eighty
                NotificationCenter.default.post(name: .scrollBudget80Reached, object: nil)
            }
        } else if percentage >= 50 {
            if currentThreshold == .none {
                currentThreshold = .fifty
                NotificationCenter.default.post(name: .scrollBudget50Reached, object: nil)
            }
        }
    }
    
    private func handleBudgetReached() {
        switch enforcementMode {
        case .hardStop:
            // Lock feed immediately
            isLocked = true
            NotificationCenter.default.post(name: .scrollBudgetLocked, object: nil)
            
        case .softStop:
            // Offer extension if available
            if softStopExtensionsUsed < enforcementMode.maxExtensions {
                NotificationCenter.default.post(
                    name: .scrollBudgetSoftStopReached,
                    object: nil,
                    userInfo: ["extensionsRemaining": enforcementMode.maxExtensions - softStopExtensionsUsed]
                )
            } else {
                // No more extensions - lock
                isLocked = true
                NotificationCenter.default.post(name: .scrollBudgetLocked, object: nil)
            }
        }
    }
    
    /// Request 5-minute extension (soft stop only)
    func requestExtension() -> Bool {
        guard enforcementMode == .softStop,
              softStopExtensionsUsed < enforcementMode.maxExtensions else {
            return false
        }
        
        softStopExtensionsUsed += 1
        dailyBudgetMinutes += 5
        
        // Update threshold to not trigger again immediately
        currentThreshold = .eighty
        
        saveUsageData()
        return true
    }
    
    // MARK: - Compulsive Reopen Detection
    
    /// Track app reopen to detect compulsive behavior
    func trackAppReopen() {
        guard isLocked else { return }
        
        // Check if reopened within 10 minutes of last close
        if let lastClose = lastAppCloseTime,
           Date().timeIntervalSince(lastClose) < 600 { // 10 minutes
            compulsiveReopenCount += 1
            
            if compulsiveReopenCount >= 3 {
                // Detected compulsive reopening - show supportive redirect
                NotificationCenter.default.post(
                    name: .compulsiveReopenDetected,
                    object: nil,
                    userInfo: ["reopenCount": compulsiveReopenCount]
                )
            }
        } else {
            // Reset if reopened after 10+ minutes
            compulsiveReopenCount = 0
        }
    }
    
    func trackAppClose() {
        lastAppCloseTime = Date()
    }
    
    // MARK: - Budget Configuration
    
    func updateBudget(minutes: Int) {
        dailyBudgetMinutes = minutes
        updateThreshold()
        saveUserSettings()
    }
    
    func updateEnforcement(mode: EnforcementMode) {
        enforcementMode = mode
        saveUserSettings()
    }
    
    func toggleExemptSection(_ section: ExemptSection) {
        if exemptSections.contains(section) {
            exemptSections.remove(section)
        } else {
            exemptSections.insert(section)
        }
        saveUserSettings()
    }
    
    func toggleEnabled() {
        isEnabled.toggle()
        saveUserSettings()
        
        if !isEnabled {
            // Reset state when disabled
            isLocked = false
            currentThreshold = .none
        }
    }
    
    // MARK: - Daily Reset
    
    private func setupDailyReset() {
        let calendar = Calendar.current
        let now = Date()
        todayDate = calendar.startOfDay(for: now).ISO8601Format()
        
        // Check if we need to reset from yesterday
        loadUsageData()
    }
    
    private func startDailyResetTimer() {
        // Reset at midnight
        Timer.publish(every: 3600, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkDailyReset()
            }
            .store(in: &cancellables)
    }
    
    private func checkDailyReset() {
        let calendar = Calendar.current
        let now = Date()
        let currentDate = calendar.startOfDay(for: now).ISO8601Format()
        
        if currentDate != todayDate {
            // New day - reset counters
            todayDate = currentDate
            todayScrollMinutes = 0
            currentThreshold = .none
            isLocked = false
            softStopExtensionsUsed = 0
            compulsiveReopenCount = 0
            
            saveUsageData()
        }
    }
    
    // MARK: - Persistence
    
    private func saveUserSettings() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let settings: [String: Any] = [
            "scrollBudgetEnabled": isEnabled,
            "dailyBudgetMinutes": dailyBudgetMinutes,
            "enforcementMode": enforcementMode.rawValue,
            "exemptSections": exemptSections.map { $0.rawValue },
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        db.collection("users").document(userId)
            .setData(["scrollBudget": settings], merge: true)
    }
    
    private func loadUserSettings() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        db.collection("users").document(userId).getDocument { [weak self] snapshot, error in
            guard let data = snapshot?.data(),
                  let budgetData = data["scrollBudget"] as? [String: Any] else {
                return
            }
            
            DispatchQueue.main.async {
                self?.isEnabled = budgetData["scrollBudgetEnabled"] as? Bool ?? false
                self?.dailyBudgetMinutes = budgetData["dailyBudgetMinutes"] as? Int ?? 30
                
                if let modeRaw = budgetData["enforcementMode"] as? String,
                   let mode = EnforcementMode(rawValue: modeRaw) {
                    self?.enforcementMode = mode
                }
                
                if let sectionsRaw = budgetData["exemptSections"] as? [String] {
                    self?.exemptSections = Set(sectionsRaw.compactMap { ExemptSection(rawValue: $0) })
                }
            }
        }
    }
    
    private func saveUsageData() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let usage: [String: Any] = [
            "date": todayDate,
            "scrollMinutes": todayScrollMinutes,
            "threshold": currentThreshold.rawValue,
            "isLocked": isLocked,
            "extensionsUsed": softStopExtensionsUsed,
            "compulsiveReopenCount": compulsiveReopenCount,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        db.collection("users").document(userId)
            .collection("scrollBudgetUsage")
            .document(todayDate)
            .setData(usage, merge: true)
    }
    
    private func loadUsageData() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        db.collection("users").document(userId)
            .collection("scrollBudgetUsage")
            .document(todayDate)
            .getDocument { [weak self] snapshot, error in
                guard let data = snapshot?.data() else { return }
                
                DispatchQueue.main.async {
                    self?.todayScrollMinutes = data["scrollMinutes"] as? Double ?? 0
                    self?.softStopExtensionsUsed = data["extensionsUsed"] as? Int ?? 0
                    self?.compulsiveReopenCount = data["compulsiveReopenCount"] as? Int ?? 0
                    self?.isLocked = data["isLocked"] as? Bool ?? false
                    
                    if let thresholdRaw = data["threshold"] as? String {
                        self?.currentThreshold = UsageThreshold(rawValue: thresholdRaw) ?? .none
                    }
                }
            }
    }
    
    // MARK: - Helper Properties
    
    var usagePercentage: Double {
        guard dailyBudgetMinutes > 0 else { return 0 }
        return min(100, (todayScrollMinutes / Double(dailyBudgetMinutes)) * 100)
    }
    
    var remainingMinutes: Int {
        max(0, dailyBudgetMinutes - Int(todayScrollMinutes))
    }
    
    var canAccessFeed: Bool {
        return !isEnabled || !isLocked
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let scrollBudget50Reached = Notification.Name("scrollBudget50Reached")
    static let scrollBudget80Reached = Notification.Name("scrollBudget80Reached")
    static let scrollBudgetSoftStopReached = Notification.Name("scrollBudgetSoftStopReached")
    static let scrollBudgetLocked = Notification.Name("scrollBudgetLocked")
    static let compulsiveReopenDetected = Notification.Name("compulsiveReopenDetected")
}
