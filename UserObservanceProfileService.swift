//
//  UserObservanceProfileService.swift
//  AMENAPP
//
//  User Observance Profile Service — manages user preferences for
//  Christian holiday engagement, denomination sensitivity, and
//  seasonal interaction tracking.
//
//  Three-tier calendar system:
//    1. global_default_calendar  → LiturgicalCalendarEngine defaults
//    2. church_calendar_override → Church-specific if user has a linked church
//    3. user_preference_filter   → User's personal observance preferences
//
//  This makes it business-ready: churches can configure what they observe,
//  and users can control what they see.
//
//  Storage: Firestore (users/{uid}/observanceProfile) + UserDefaults cache.
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Observance Engagement Level

/// How intensely the user wants seasonal content.
enum ObservanceEngagementLevel: String, Codable, CaseIterable {
    case full       = "full"       // All seasonal features active
    case moderate   = "moderate"   // Major holidays only, fewer prompts
    case minimal    = "minimal"    // Only day-of major holidays
    case off        = "off"        // No seasonal content

    var displayName: String {
        switch self {
        case .full:     return "Full"
        case .moderate: return "Moderate"
        case .minimal:  return "Minimal"
        case .off:      return "Off"
        }
    }

    var description: String {
        switch self {
        case .full:     return "All seasonal features — reflections, prompts, church events, and notifications"
        case .moderate: return "Major holidays and key prompts only"
        case .minimal:  return "Day-of reminders for Easter and Christmas only"
        case .off:      return "No seasonal content or notifications"
        }
    }
}

// MARK: - Reminder Preference

enum SeasonalReminderPreference: String, Codable, CaseIterable {
    case morningReflection   = "morning"    // 7-8 AM
    case eveningReflection   = "evening"    // 7-8 PM
    case both                = "both"
    case none                = "none"

    var displayName: String {
        switch self {
        case .morningReflection: return "Morning"
        case .eveningReflection: return "Evening"
        case .both:              return "Morning & Evening"
        case .none:              return "None"
        }
    }
}

// MARK: - User Observance Profile

struct UserObservanceProfile: Codable {
    let userId: String
    var preferredTradition: DenominationProfile
    var engagementLevel: ObservanceEngagementLevel
    var interestedHolidays: [HolidayType]       // Holidays user wants content for
    var mutedHolidayTypes: [HolidayType]         // Holidays user has muted
    var reminderPreference: SeasonalReminderPreference
    var notificationsEnabled: Bool
    var linkedChurchId: String?                  // If user follows a church
    var lastHolidayInteractionAt: Date?
    var activeJourneyIds: [String]               // Current reflection journey IDs
    var completedJourneyCount: Int
    var updatedAt: Date

    /// Returns whether a specific holiday should be shown to this user.
    func shouldShow(holiday: HolidayType) -> Bool {
        guard engagementLevel != .off else { return false }
        if mutedHolidayTypes.contains(holiday) { return false }

        switch engagementLevel {
        case .full:
            return preferredTradition.observedHolidays.contains(holiday)
        case .moderate:
            return holiday.priorityWeight >= 7 && preferredTradition.observedHolidays.contains(holiday)
        case .minimal:
            return holiday == .easter || holiday == .christmas
        case .off:
            return false
        }
    }

    /// Returns whether seasonal Berean prompts should be active.
    var seasonalBereanActive: Bool {
        engagementLevel == .full || engagementLevel == .moderate
    }

    /// Returns whether seasonal notifications should be sent.
    var seasonalNotificationsActive: Bool {
        notificationsEnabled && engagementLevel != .off && reminderPreference != .none
    }

    static func defaultProfile(userId: String) -> UserObservanceProfile {
        UserObservanceProfile(
            userId: userId,
            preferredTradition: .nonDenominational,
            engagementLevel: .moderate,
            interestedHolidays: [.christmas, .easter, .goodFriday, .pentecost],
            mutedHolidayTypes: [],
            reminderPreference: .morningReflection,
            notificationsEnabled: true,
            linkedChurchId: nil,
            lastHolidayInteractionAt: nil,
            activeJourneyIds: [],
            completedJourneyCount: 0,
            updatedAt: Date()
        )
    }
}

// MARK: - Service

@MainActor
final class UserObservanceProfileService: ObservableObject {

    static let shared = UserObservanceProfileService()

    @Published private(set) var profile: UserObservanceProfile?
    @Published private(set) var isLoading = false

    private let db = Firestore.firestore()
    private let cacheKey = "user_observance_profile_v1"

    private init() {
        loadCachedProfile()
    }

    // MARK: - Load Profile

    /// Loads the user's observance profile from Firestore.
    func loadProfile() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        // Return cached if fresh
        if let cached = profile,
           Date().timeIntervalSince(cached.updatedAt) < 3600 {
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let doc = try await db.collection("users").document(uid)
                .collection("settings")
                .document("observanceProfile")
                .getDocument()

            if doc.exists, let data = try? doc.data(as: UserObservanceProfile.self) {
                self.profile = data
                cacheProfile(data)

                // Apply denomination to calendar engine
                LiturgicalCalendarEngine.shared.denominationProfile = data.preferredTradition
            } else {
                // Create default profile
                let defaultProfile = UserObservanceProfile.defaultProfile(userId: uid)
                self.profile = defaultProfile
                await saveProfile(defaultProfile)
            }

        } catch {
            dlog("[ObservanceProfile] Load failed: \(error.localizedDescription)")
            // Use cached or default
            if profile == nil {
                profile = UserObservanceProfile.defaultProfile(userId: uid)
            }
        }
    }

    // MARK: - Update Profile

    /// Updates the user's observance profile.
    func updateProfile(_ updates: (inout UserObservanceProfile) -> Void) async {
        guard var current = profile else { return }
        updates(&current)
        current = UserObservanceProfile(
            userId: current.userId,
            preferredTradition: current.preferredTradition,
            engagementLevel: current.engagementLevel,
            interestedHolidays: current.interestedHolidays,
            mutedHolidayTypes: current.mutedHolidayTypes,
            reminderPreference: current.reminderPreference,
            notificationsEnabled: current.notificationsEnabled,
            linkedChurchId: current.linkedChurchId,
            lastHolidayInteractionAt: current.lastHolidayInteractionAt,
            activeJourneyIds: current.activeJourneyIds,
            completedJourneyCount: current.completedJourneyCount,
            updatedAt: Date()
        )
        self.profile = current
        cacheProfile(current)

        // Apply denomination to calendar engine
        LiturgicalCalendarEngine.shared.denominationProfile = current.preferredTradition

        await saveProfile(current)
    }

    /// Sets the preferred denomination/tradition.
    func setTradition(_ tradition: DenominationProfile) async {
        await updateProfile { $0.preferredTradition = tradition }
    }

    /// Sets the engagement level.
    func setEngagementLevel(_ level: ObservanceEngagementLevel) async {
        await updateProfile { $0.engagementLevel = level }
    }

    /// Mutes a specific holiday type.
    func muteHoliday(_ holiday: HolidayType) async {
        await updateProfile {
            if !$0.mutedHolidayTypes.contains(holiday) {
                $0.mutedHolidayTypes.append(holiday)
            }
        }
    }

    /// Unmutes a specific holiday type.
    func unmuteHoliday(_ holiday: HolidayType) async {
        await updateProfile {
            $0.mutedHolidayTypes.removeAll { $0 == holiday }
        }
    }

    /// Sets the reminder preference.
    func setReminderPreference(_ pref: SeasonalReminderPreference) async {
        await updateProfile { $0.reminderPreference = pref }
    }

    /// Links a church to the user's profile.
    func linkChurch(_ churchId: String) async {
        await updateProfile { $0.linkedChurchId = churchId }
    }

    /// Records a holiday interaction (for tracking engagement).
    func recordInteraction() async {
        await updateProfile { $0.lastHolidayInteractionAt = Date() }
    }

    // MARK: - Convenience Queries

    /// Whether seasonal content should be shown to this user.
    var shouldShowSeasonalContent: Bool {
        guard let profile = profile else { return true } // Default to showing
        return profile.engagementLevel != .off
    }

    /// Whether a specific holiday should be shown.
    func shouldShow(holiday: HolidayType) -> Bool {
        guard let profile = profile else { return true }
        return profile.shouldShow(holiday: holiday)
    }

    /// Whether Berean should include seasonal context.
    var bereanSeasonalActive: Bool {
        profile?.seasonalBereanActive ?? true
    }

    /// Whether the user has a linked church.
    var hasLinkedChurch: Bool {
        profile?.linkedChurchId != nil
    }

    // MARK: - Persistence

    private func saveProfile(_ profile: UserObservanceProfile) async {
        do {
            let data = try Firestore.Encoder().encode(profile)
            try await db.collection("users").document(profile.userId)
                .collection("settings")
                .document("observanceProfile")
                .setData(data, merge: true)
        } catch {
            dlog("[ObservanceProfile] Save failed: \(error.localizedDescription)")
        }
    }

    private func loadCachedProfile() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode(UserObservanceProfile.self, from: data) else {
            return
        }
        profile = cached
        LiturgicalCalendarEngine.shared.denominationProfile = cached.preferredTradition
    }

    private func cacheProfile(_ profile: UserObservanceProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    // MARK: - Reset

    func reset() {
        profile = nil
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }
}
