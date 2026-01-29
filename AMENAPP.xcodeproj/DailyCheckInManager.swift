//
//  DailyCheckInManager.swift
//  AMENAPP
//
//  Manages daily spiritual check-in state
//

import SwiftUI
import Combine

@MainActor
class DailyCheckInManager: ObservableObject {
    static let shared = DailyCheckInManager()
    
    @Published var shouldShowCheckIn: Bool = false
    @Published var hasAnsweredToday: Bool = false
    @Published var userAnsweredYes: Bool = false
    
    private let lastCheckInDateKey = "lastCheckInDate"
    private let lastAnswerKey = "lastCheckInAnswer"
    private let hasAnsweredTodayKey = "hasAnsweredToday"
    
    private init() {
        checkIfShouldShowCheckIn()
    }
    
    // MARK: - Public Methods
    
    /// Check if we should show the daily check-in popup
    func checkIfShouldShowCheckIn() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Get last check-in date from UserDefaults
        if let lastCheckInTimestamp = UserDefaults.standard.object(forKey: lastCheckInDateKey) as? Double {
            let lastCheckInDate = Date(timeIntervalSince1970: lastCheckInTimestamp)
            let lastCheckInDay = calendar.startOfDay(for: lastCheckInDate)
            
            // Check if it's a new day
            if today > lastCheckInDay {
                // New day - show check-in
                shouldShowCheckIn = true
                hasAnsweredToday = false
                userAnsweredYes = false
            } else {
                // Same day - check if user already answered
                hasAnsweredToday = UserDefaults.standard.bool(forKey: hasAnsweredTodayKey)
                shouldShowCheckIn = false
                
                if hasAnsweredToday {
                    userAnsweredYes = UserDefaults.standard.bool(forKey: lastAnswerKey)
                }
            }
        } else {
            // First time - show check-in
            shouldShowCheckIn = true
            hasAnsweredToday = false
            userAnsweredYes = false
        }
    }
    
    /// Record the user's answer
    func recordAnswer(_ answeredYes: Bool) {
        let now = Date()
        
        // Save to UserDefaults
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: lastCheckInDateKey)
        UserDefaults.standard.set(answeredYes, forKey: lastAnswerKey)
        UserDefaults.standard.set(true, forKey: hasAnsweredTodayKey)
        
        // Update state
        hasAnsweredToday = true
        userAnsweredYes = answeredYes
        shouldShowCheckIn = false
    }
    
    /// Reset for testing purposes
    func reset() {
        UserDefaults.standard.removeObject(forKey: lastCheckInDateKey)
        UserDefaults.standard.removeObject(forKey: lastAnswerKey)
        UserDefaults.standard.removeObject(forKey: hasAnsweredTodayKey)
        
        shouldShowCheckIn = true
        hasAnsweredToday = false
        userAnsweredYes = false
    }
    
    /// Check on app becoming active
    func handleAppBecameActive() {
        checkIfShouldShowCheckIn()
    }
}
