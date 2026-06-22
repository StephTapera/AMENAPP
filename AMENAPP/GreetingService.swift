//
//  GreetingService.swift
//  AMENAPP
//
//  Smart contextual greeting system with privacy-first personalization
//

import SwiftUI
import Combine

/// Manages personalized greetings with priority-based logic and user permissions
@MainActor
class GreetingService: ObservableObject {
    static let shared = GreetingService()
    
    @Published var currentGreeting: GreetingModel = GreetingModel(text: "Welcome", type: .generic)
    @Published var userFirstName: String = ""
    
    // User preferences (stored in UserDefaults)
    @AppStorage("greetingUseFirstName") var useFirstName: Bool = false
    @AppStorage("greetingUseBirthday") var useBirthday: Bool = false
    @AppStorage("greetingUseLocalTime") var useLocalTime: Bool = true
    @AppStorage("greetingShowFaithBased") var showFaithBased: Bool = false
    @AppStorage("userBirthday") var userBirthdayString: String = ""
    
    private var updateTimer: Timer?
    
    private init() {
        loadUserProfile()
        updateGreeting()
        startAutoUpdate()
    }
    
    // MARK: - Public Methods
    
    /// Manually refresh the greeting (call on app foreground)
    func refreshGreeting() {
        loadUserProfile()
        updateGreeting()
    }
    
    /// Update greeting based on current context and permissions
    func updateGreeting() {
        let greeting = determineGreeting()
        
        // Smooth update on main thread
        DispatchQueue.main.async { [weak self] in
            self?.currentGreeting = greeting
        }
    }
    
    // MARK: - Private Logic
    
    private func loadUserProfile() {
        // Load from UserService or local cache
        if let user = UserService.shared.currentUser {
            // Extract first name from displayName
            userFirstName = user.displayName.components(separatedBy: " ").first ?? user.displayName
        }
    }
    
    /// Priority-based greeting determination
    private func determineGreeting() -> GreetingModel {
        // Priority 1: Birthday greeting
        if useBirthday, isTodayUserBirthday() {
            return GreetingModel(
                text: formatGreeting("Happy Birthday", withName: useFirstName),
                type: .birthday
            )
        }
        
        // Priority 2: Special day greetings (faith-based)
        if showFaithBased, let specialGreeting = getSpecialDayGreeting() {
            return specialGreeting
        }
        
        // Priority 3: Time-of-day greeting
        if useLocalTime {
            return getTimeBasedGreeting()
        }
        
        // Fallback: Generic welcome
        return GreetingModel(
            text: useFirstName ? formatGreeting("Welcome", withName: true) : "Welcome",
            type: .generic
        )
    }
    
    private func formatGreeting(_ base: String, withName: Bool) -> String {
        if withName && !userFirstName.isEmpty {
            return "\(base), \(userFirstName)"
        }
        return base
    }
    
    private func getTimeBasedGreeting() -> GreetingModel {
        let hour = Calendar.current.component(.hour, from: Date())
        
        let timeOfDay: String
        let type: GreetingType
        
        switch hour {
        case 0..<12:
            timeOfDay = "Good Morning"
            type = .morning
        case 12..<17:
            timeOfDay = "Good Afternoon"
            type = .afternoon
        default:
            timeOfDay = "Good Evening"
            type = .evening
        }
        
        return GreetingModel(
            text: formatGreeting(timeOfDay, withName: useFirstName),
            type: type
        )
    }
    
    private func getSpecialDayGreeting() -> GreetingModel? {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        
        // Sunday
        if weekday == 1 {
            return GreetingModel(
                text: formatGreeting("Blessed Sunday", withName: useFirstName),
                type: .sunday
            )
        }
        
        // Easter (simplified - should use proper Easter calculation)
        // New Year's Day
        if calendar.component(.month, from: today) == 1,
           calendar.component(.day, from: today) == 1 {
            return GreetingModel(
                text: formatGreeting("Happy New Year", withName: useFirstName),
                type: .holiday
            )
        }
        
        // Christmas
        if calendar.component(.month, from: today) == 12,
           calendar.component(.day, from: today) == 25 {
            return GreetingModel(
                text: formatGreeting("Merry Christmas", withName: useFirstName),
                type: .holiday
            )
        }
        
        return nil
    }
    
    private func isTodayUserBirthday() -> Bool {
        guard !userBirthdayString.isEmpty else { return false }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        guard let birthday = formatter.date(from: userBirthdayString) else { return false }
        
        let calendar = Calendar.current
        let today = Date()
        
        let todayMonth = calendar.component(.month, from: today)
        let todayDay = calendar.component(.day, from: today)
        let birthdayMonth = calendar.component(.month, from: birthday)
        let birthdayDay = calendar.component(.day, from: birthday)
        
        return todayMonth == birthdayMonth && todayDay == birthdayDay
    }
    
    // MARK: - Auto Update
    
    private func startAutoUpdate() {
        // Update every hour to catch time-of-day transitions
        updateTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateGreeting()
            }
        }
    }
    
    deinit {
        updateTimer?.invalidate()
    }
}

// MARK: - Models

struct GreetingModel: Equatable {
    let text: String
    let type: GreetingType
    let timestamp: Date = Date()
    
    static func == (lhs: GreetingModel, rhs: GreetingModel) -> Bool {
        lhs.text == rhs.text && lhs.type == rhs.type
    }
}

enum GreetingType {
    case morning
    case afternoon
    case evening
    case birthday
    case sunday
    case holiday
    case welcome
    case generic
}
