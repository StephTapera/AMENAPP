//
//  ChristianDatingService.swift
//  AMENAPP
//
//  Created by Steph on 1/19/26.
//

import Foundation
import CoreLocation
import Combine

@MainActor
class ChristianDatingService: ObservableObject {
    static let shared = ChristianDatingService()
    
    // MARK: - Published Properties
    
    @Published var currentUserProfile: DatingProfile?
    @Published var discoveryProfiles: [DatingProfile] = []
    @Published var matches: [DatingMatch] = []
    @Published var conversations: [String: [DatingMessage]] = [:]
    @Published var blockedProfiles: Set<String> = []
    @Published var swipedProfiles: Set<String> = [] // Already swiped (like or pass)
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Local cache keys
    private let profileKey = "dating_current_profile"
    private let matchesKey = "dating_matches"
    private let swipedProfilesKey = "dating_swiped_profiles"
    
    private init() {
        loadCachedData()
    }
    
    // MARK: - Profile Management
    
    func createDatingProfile(
        name: String,
        age: Int,
        gender: String,
        denomination: String,
        churchName: String?,
        churchCity: String?,
        faithLevel: String,
        bio: String,
        interests: [String],
        priorities: [String],
        dealBreakers: [String],
        meetingPreference: String,
        phoneNumber: String,
        emergencyContact: String
    ) async throws -> DatingProfile {
        isLoading = true
        defer { isLoading = false }
        
        // TODO: Replace with actual API call
        // let response = try await APIClient.post("/api/dating/profiles", body: profileData)
        
        // Simulate network delay
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        let profile = DatingProfile(
            id: UUID(),
            userId: getCurrentUserId(),
            name: name,
            age: age,
            gender: gender,
            locationLat: nil,
            locationLon: nil,
            locationCity: churchCity ?? "",
            photos: [],
            denomination: denomination,
            churchName: churchName,
            churchCity: churchCity,
            faithLevel: faithLevel,
            faithYears: nil,
            testimony: nil,
            bio: bio,
            interests: interests,
            priorities: priorities,
            dealBreakers: dealBreakers,
            lookingFor: "Dating",
            preferredGenderToMatch: gender == "Male" ? "Female" : "Male",
            preferredAgeMin: max(18, age - 5),
            preferredAgeMax: min(99, age + 10),
            preferredMaxDistance: 50,
            preferredDenominations: [],
            preferredFaithLevels: [],
            isPhoneVerified: false,
            isChurchVerified: false,
            emergencyContact: emergencyContact,
            meetingPreference: meetingPreference,
            reportCount: 0,
            isBanned: false,
            createdAt: Date(),
            lastActive: Date(),
            isOnline: true
        )
        
        currentUserProfile = profile
        saveCachedProfile(profile)
        
        return profile
    }
    
    func updateProfile(_ profile: DatingProfile) async throws {
        isLoading = true
        defer { isLoading = false }
        
        // TODO: Replace with actual API call
        // try await APIClient.put("/api/dating/profiles/\(profile.id)", body: profile)
        
        try await Task.sleep(nanoseconds: 500_000_000)
        
        currentUserProfile = profile
        saveCachedProfile(profile)
    }
    
    func deleteProfile() async throws {
        isLoading = true
        defer { isLoading = false }
        
        guard let profile = currentUserProfile else { return }
        
        // TODO: Replace with actual API call
        // try await APIClient.delete("/api/dating/profiles/\(profile.id)")
        
        try await Task.sleep(nanoseconds: 500_000_000)
        
        currentUserProfile = nil
        UserDefaults.standard.removeObject(forKey: profileKey)
    }
    
    func fetchCurrentUserProfile() async throws -> DatingProfile? {
        isLoading = true
        defer { isLoading = false }
        
        // TODO: Replace with actual API call
        // let profile = try await APIClient.get("/api/dating/profile/me")
        
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // For now, return cached or nil
        return currentUserProfile
    }
    
    // MARK: - Discovery
    
    func fetchDiscoveryProfiles(
        location: CLLocationCoordinate2D? = nil,
        filters: ProfileFilters? = nil
    ) async throws -> [DatingProfile] {
        isLoading = true
        defer { isLoading = false }
        
        // TODO: Replace with actual API call
        // let profiles = try await APIClient.get("/api/dating/discover", queryParams: params)
        
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // For now, use sample data and filter out already swiped
        let allProfiles = DatingProfile.sampleProfiles()
        
        discoveryProfiles = allProfiles.filter { profile in
            // Filter out already swiped profiles
            !swipedProfiles.contains(profile.userId) &&
            // Filter out blocked profiles
            !blockedProfiles.contains(profile.userId) &&
            // Filter out own profile
            profile.userId != getCurrentUserId()
        }
        
        // Apply local filtering if needed
        if let filters = filters {
            discoveryProfiles = applyFilters(to: discoveryProfiles, filters: filters)
        }
        
        return discoveryProfiles
    }
    
    func refreshDiscoveryQueue() async throws {
        // Clear swiped profiles cache and fetch new batch
        swipedProfiles.removeAll()
        saveSwipedProfiles()
        _ = try await fetchDiscoveryProfiles()
    }
    
    private func applyFilters(to profiles: [DatingProfile], filters: ProfileFilters) -> [DatingProfile] {
        return profiles.filter { profile in
            // Age filter
            if let ageRange = filters.ageRange {
                guard ageRange.contains(profile.age) else { return false }
            }
            
            // Denomination filter
            if let denominations = filters.denominations, !denominations.isEmpty {
                guard denominations.contains(profile.denomination) else { return false }
            }
            
            // Faith level filter
            if let faithLevels = filters.faithLevels, !faithLevels.isEmpty {
                guard faithLevels.contains(profile.faithLevel) else { return false }
            }
            
            // Church verification filter
            if filters.mustHaveChurchVerification {
                guard profile.isChurchVerified else { return false }
            }
            
            return true
        }
    }
    
    // MARK: - Swipe Actions
    
    func likeProfile(_ profileId: String) async throws -> Bool {
        isLoading = true
        defer { isLoading = false }
        
        // Record swipe
        swipedProfiles.insert(profileId)
        saveSwipedProfiles()
        
        // TODO: Replace with actual API call
        // let response = try await APIClient.post("/api/dating/swipes", body: swipeData)
        // return response.isMatch
        
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Simulate match (20% chance for demo)
        let isMatch = Int.random(in: 1...5) == 1
        
        if isMatch {
            // Create a match
            let match = DatingMatch(
                id: UUID(),
                user1Id: getCurrentUserId(),
                user2Id: profileId,
                matchedAt: Date(),
                conversationId: UUID().uuidString,
                isActive: true,
                user1LastRead: nil,
                user2LastRead: nil
            )
            matches.append(match)
            saveMatches()
        }
        
        // Remove from discovery
        discoveryProfiles.removeAll { $0.userId == profileId }
        
        return isMatch
    }
    
    func passProfile(_ profileId: String) async throws {
        // Record swipe
        swipedProfiles.insert(profileId)
        saveSwipedProfiles()
        
        // TODO: Replace with actual API call
        // try await APIClient.post("/api/dating/swipes", body: swipeData)
        
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Remove from discovery
        discoveryProfiles.removeAll { $0.userId == profileId }
    }
    
    func superLikeProfile(_ profileId: String) async throws -> Bool {
        // Same as like but with higher priority/notification
        isLoading = true
        defer { isLoading = false }
        
        swipedProfiles.insert(profileId)
        saveSwipedProfiles()
        
        // TODO: Replace with actual API call
        
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Simulate match (40% chance for super like)
        let isMatch = Int.random(in: 1...5) <= 2
        
        if isMatch {
            let match = DatingMatch(
                id: UUID(),
                user1Id: getCurrentUserId(),
                user2Id: profileId,
                matchedAt: Date(),
                conversationId: UUID().uuidString,
                isActive: true,
                user1LastRead: nil,
                user2LastRead: nil
            )
            matches.append(match)
            saveMatches()
        }
        
        discoveryProfiles.removeAll { $0.userId == profileId }
        
        return isMatch
    }
    
    func undoLastSwipe() async throws {
        // Premium feature - would need to track swipe history
        // TODO: Implement with backend support
        throw DatingServiceError.featureNotAvailable
    }
    
    // MARK: - Matches
    
    func fetchMatches() async throws -> [DatingMatch] {
        isLoading = true
        defer { isLoading = false }
        
        // TODO: Replace with actual API call
        // let matches = try await APIClient.get("/api/dating/matches")
        
        try await Task.sleep(nanoseconds: 500_000_000)
        
        return matches
    }
    
    func unmatch(_ matchId: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        // TODO: Replace with actual API call
        // try await APIClient.delete("/api/dating/matches/\(matchId)")
        
        try await Task.sleep(nanoseconds: 500_000_000)
        
        matches.removeAll { $0.id.uuidString == matchId }
        conversations.removeValue(forKey: matchId)
        saveMatches()
    }
    
    // MARK: - Messaging
    
    func fetchMessages(for matchId: String) async throws -> [DatingMessage] {
        isLoading = true
        defer { isLoading = false }
        
        // TODO: Replace with actual API call
        // let messages = try await APIClient.get("/api/dating/matches/\(matchId)/messages")
        
        try await Task.sleep(nanoseconds: 500_000_000)
        
        return conversations[matchId] ?? []
    }
    
    func sendMessage(
        matchId: String,
        receiverId: String,
        content: String,
        type: MessageType = .text
    ) async throws -> DatingMessage {
        isLoading = true
        defer { isLoading = false }
        
        // TODO: Replace with actual API call
        // let message = try await APIClient.post("/api/dating/matches/\(matchId)/messages", body: messageData)
        
        try await Task.sleep(nanoseconds: 300_000_000)
        
        let message = DatingMessage(
            id: UUID(),
            matchId: matchId,
            senderId: getCurrentUserId(),
            receiverId: receiverId,
            content: content,
            timestamp: Date(),
            isRead: false,
            messageType: type
        )
        
        if conversations[matchId] != nil {
            conversations[matchId]?.append(message)
        } else {
            conversations[matchId] = [message]
        }
        
        return message
    }
    
    func markMessagesAsRead(matchId: String) async throws {
        // TODO: Replace with actual API call
        // try await APIClient.put("/api/dating/matches/\(matchId)/read")
        
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Update local messages
        if var messages = conversations[matchId] {
            for index in messages.indices {
                messages[index].isRead = true
            }
            conversations[matchId] = messages
        }
    }
    
    // MARK: - Safety & Verification
    
    func verifyPhoneNumber(_ phoneNumber: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        // TODO: Replace with actual API call (Twilio, Firebase Auth, etc.)
        // try await APIClient.post("/api/dating/verify/phone", body: ["phoneNumber": phoneNumber])
        
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // In production, this would send an SMS with a verification code
        print("📱 Verification code sent to \(phoneNumber)")
    }
    
    func confirmPhoneVerification(code: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        // TODO: Replace with actual API call
        // try await APIClient.post("/api/dating/verify/phone/confirm", body: ["code": code])
        
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Update profile
        if var profile = currentUserProfile {
            profile.isPhoneVerified = true
            currentUserProfile = profile
            saveCachedProfile(profile)
        }
    }
    
    func requestChurchVerification() async throws {
        isLoading = true
        defer { isLoading = false }
        
        // TODO: Replace with actual API call
        // try await APIClient.post("/api/dating/verify/church")
        
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // This would trigger an admin review process
        print("⛪️ Church verification request submitted for admin review")
    }
    
    func reportProfile(
        profileId: String,
        reason: DatingReportReason,
        description: String?
    ) async throws {
        isLoading = true
        defer { isLoading = false }
        
        let report = ProfileReport(
            id: UUID(),
            reporterId: getCurrentUserId(),
            reportedProfileId: profileId,
            reason: reason,
            description: description,
            timestamp: Date(),
            reviewStatus: .pending
        )
        
        // TODO: Replace with actual API call
        // try await APIClient.post("/api/dating/reports", body: report)
        
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Remove from discovery
        discoveryProfiles.removeAll { $0.userId == profileId }
        
        print("⚠️ Profile reported: \(profileId) for \(reason.rawValue)")
    }
    
    func blockProfile(_ profileId: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        // TODO: Replace with actual API call
        // try await APIClient.post("/api/dating/blocks", body: ["profileId": profileId])
        
        try await Task.sleep(nanoseconds: 500_000_000)
        
        blockedProfiles.insert(profileId)
        
        // Remove from discovery and matches
        discoveryProfiles.removeAll { $0.userId == profileId }
        matches.removeAll { $0.user1Id == profileId || $0.user2Id == profileId }
        
        saveBlockedProfiles()
    }
    
    func unblockProfile(_ profileId: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        // TODO: Replace with actual API call
        // try await APIClient.delete("/api/dating/blocks/\(profileId)")
        
        try await Task.sleep(nanoseconds: 500_000_000)
        
        blockedProfiles.remove(profileId)
        saveBlockedProfiles()
    }
    
    // MARK: - Photo Management
    
    func uploadPhoto(_ imageData: Data) async throws -> String {
        isLoading = true
        defer { isLoading = false }
        
        // TODO: Replace with actual API call
        // Upload to cloud storage (S3, Firebase Storage, etc.)
        // let photoUrl = try await APIClient.uploadImage("/api/dating/photos", imageData: imageData)
        
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        // For now, return a placeholder URL
        let photoUrl = "https://placeholder.com/\(UUID().uuidString).jpg"
        
        // Add to profile
        if var profile = currentUserProfile {
            profile.photos.append(photoUrl)
            currentUserProfile = profile
            saveCachedProfile(profile)
        }
        
        return photoUrl
    }
    
    func deletePhoto(_ photoUrl: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        // TODO: Replace with actual API call
        // try await APIClient.delete("/api/dating/photos", body: ["url": photoUrl])
        
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Remove from profile
        if var profile = currentUserProfile {
            profile.photos.removeAll { $0 == photoUrl }
            currentUserProfile = profile
            saveCachedProfile(profile)
        }
    }
    
    func reorderPhotos(_ photoUrls: [String]) async throws {
        isLoading = true
        defer { isLoading = false }
        
        // TODO: Replace with actual API call
        // try await APIClient.put("/api/dating/photos/order", body: ["photos": photoUrls])
        
        try await Task.sleep(nanoseconds: 300_000_000)
        
        // Update profile
        if var profile = currentUserProfile {
            profile.photos = photoUrls
            currentUserProfile = profile
            saveCachedProfile(profile)
        }
    }
    
    // MARK: - Helper Methods
    
    private func getCurrentUserId() -> String {
        // TODO: Get from actual auth service
        return "current-user-\(UUID().uuidString)"
    }
    
    // MARK: - Caching
    
    private func loadCachedData() {
        // Load profile
        if let data = UserDefaults.standard.data(forKey: profileKey),
           let profile = try? JSONDecoder().decode(DatingProfile.self, from: data) {
            currentUserProfile = profile
        }
        
        // Load matches
        if let data = UserDefaults.standard.data(forKey: matchesKey),
           let cachedMatches = try? JSONDecoder().decode([DatingMatch].self, from: data) {
            matches = cachedMatches
        }
        
        // Load swiped profiles
        if let swipedArray = UserDefaults.standard.array(forKey: swipedProfilesKey) as? [String] {
            swipedProfiles = Set(swipedArray)
        }
    }
    
    private func saveCachedProfile(_ profile: DatingProfile) {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: profileKey)
        }
    }
    
    private func saveMatches() {
        if let data = try? JSONEncoder().encode(matches) {
            UserDefaults.standard.set(data, forKey: matchesKey)
        }
    }
    
    private func saveSwipedProfiles() {
        UserDefaults.standard.set(Array(swipedProfiles), forKey: swipedProfilesKey)
    }
    
    private func saveBlockedProfiles() {
        // Could cache this too if needed
    }
}

// MARK: - Service Errors

enum DatingServiceError: LocalizedError {
    case notAuthenticated
    case profileNotFound
    case featureNotAvailable
    case networkError
    case invalidData
    case banned
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please sign in to use Christian Dating"
        case .profileNotFound:
            return "Dating profile not found"
        case .featureNotAvailable:
            return "This feature is not available yet"
        case .networkError:
            return "Network connection error. Please try again."
        case .invalidData:
            return "Invalid data provided"
        case .banned:
            return "Your account has been suspended"
        }
    }
}
