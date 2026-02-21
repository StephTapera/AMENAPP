//
//  UserModel.swift
//  AMENAPP
//
//  Created by Steph on 1/19/26.
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

/// User model for Firebase Firestore
struct UserModel: Codable, Identifiable {
    @DocumentID var id: String?
    var email: String
    var displayName: String
    var username: String  // Unique username (e.g., @johndoe)
    var initials: String
    var bio: String?
    var profileImageURL: String?
    var createdAt: Date
    var updatedAt: Date
    
    // Social stats
    var followersCount: Int
    var followingCount: Int
    var postsCount: Int
    
    // Preferences
    var isPrivate: Bool
    var notificationsEnabled: Bool
    
    // Notification preferences
    var pushNotificationsEnabled: Bool
    var emailNotificationsEnabled: Bool
    var notifyOnLikes: Bool
    var notifyOnComments: Bool
    var notifyOnFollows: Bool
    var notifyOnMentions: Bool
    var notifyOnPrayerRequests: Bool
    
    // Privacy settings
    var allowMessagesFromEveryone: Bool
    var showActivityStatus: Bool
    var allowTagging: Bool
    
    // Profile visibility settings
    var showInterests: Bool
    var showSocialLinks: Bool
    var showBio: Bool
    var showFollowerCount: Bool
    var showFollowingCount: Bool
    var showSavedPosts: Bool
    var showReposts: Bool
    
    // Security settings
    var loginAlerts: Bool
    var showSensitiveContent: Bool
    var requirePasswordForPurchases: Bool
    
    // Account change tracking
    var lastUsernameChange: Date?
    var lastDisplayNameChange: Date?
    var pendingUsernameChange: String?
    var pendingDisplayNameChange: String?
    var usernameChangeRequestDate: Date?
    var displayNameChangeRequestDate: Date?
    
    // Onboarding data
    var interests: [String]?
    var goals: [String]?
    var preferredPrayerTime: String?
    var hasCompletedOnboarding: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName
        case username
        case initials
        case bio
        case profileImageURL
        case createdAt
        case updatedAt
        case followersCount
        case followingCount
        case postsCount
        case isPrivate
        case notificationsEnabled
        case pushNotificationsEnabled
        case emailNotificationsEnabled
        case notifyOnLikes
        case notifyOnComments
        case notifyOnFollows
        case notifyOnMentions
        case notifyOnPrayerRequests
        case allowMessagesFromEveryone
        case showActivityStatus
        case allowTagging
        case showInterests
        case showSocialLinks
        case showBio
        case showFollowerCount
        case showFollowingCount
        case showSavedPosts
        case showReposts
        case loginAlerts
        case showSensitiveContent
        case requirePasswordForPurchases
        case lastUsernameChange
        case lastDisplayNameChange
        case pendingUsernameChange
        case pendingDisplayNameChange
        case usernameChangeRequestDate
        case displayNameChangeRequestDate
        case interests
        case goals
        case preferredPrayerTime
        case hasCompletedOnboarding
    }
    
    // ✅ Custom decoder for backward compatibility
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Required fields
        email = try container.decode(String.self, forKey: .email)
        displayName = try container.decode(String.self, forKey: .displayName)
        username = try container.decode(String.self, forKey: .username)
        
        // Optional fields with defaults
        id = try container.decodeIfPresent(String.self, forKey: .id)
        initials = try container.decodeIfPresent(String.self, forKey: .initials) ?? String(displayName.prefix(2)).uppercased()
        bio = try container.decodeIfPresent(String.self, forKey: .bio)
        profileImageURL = try container.decodeIfPresent(String.self, forKey: .profileImageURL)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        
        // Social stats
        followersCount = try container.decodeIfPresent(Int.self, forKey: .followersCount) ?? 0
        followingCount = try container.decodeIfPresent(Int.self, forKey: .followingCount) ?? 0
        postsCount = try container.decodeIfPresent(Int.self, forKey: .postsCount) ?? 0
        
        // Preferences
        isPrivate = try container.decodeIfPresent(Bool.self, forKey: .isPrivate) ?? false
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        pushNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .pushNotificationsEnabled) ?? true
        emailNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .emailNotificationsEnabled) ?? true
        notifyOnLikes = try container.decodeIfPresent(Bool.self, forKey: .notifyOnLikes) ?? true
        notifyOnComments = try container.decodeIfPresent(Bool.self, forKey: .notifyOnComments) ?? true
        notifyOnFollows = try container.decodeIfPresent(Bool.self, forKey: .notifyOnFollows) ?? true
        notifyOnMentions = try container.decodeIfPresent(Bool.self, forKey: .notifyOnMentions) ?? true
        notifyOnPrayerRequests = try container.decodeIfPresent(Bool.self, forKey: .notifyOnPrayerRequests) ?? true
        allowMessagesFromEveryone = try container.decodeIfPresent(Bool.self, forKey: .allowMessagesFromEveryone) ?? true
        showActivityStatus = try container.decodeIfPresent(Bool.self, forKey: .showActivityStatus) ?? true
        allowTagging = try container.decodeIfPresent(Bool.self, forKey: .allowTagging) ?? true
        
        // ✅ Profile visibility with defaults
        showInterests = try container.decodeIfPresent(Bool.self, forKey: .showInterests) ?? true
        showSocialLinks = try container.decodeIfPresent(Bool.self, forKey: .showSocialLinks) ?? true
        showBio = try container.decodeIfPresent(Bool.self, forKey: .showBio) ?? true
        showFollowerCount = try container.decodeIfPresent(Bool.self, forKey: .showFollowerCount) ?? true
        showFollowingCount = try container.decodeIfPresent(Bool.self, forKey: .showFollowingCount) ?? true
        showSavedPosts = try container.decodeIfPresent(Bool.self, forKey: .showSavedPosts) ?? false
        showReposts = try container.decodeIfPresent(Bool.self, forKey: .showReposts) ?? true
        
        // Security settings
        loginAlerts = try container.decodeIfPresent(Bool.self, forKey: .loginAlerts) ?? true
        showSensitiveContent = try container.decodeIfPresent(Bool.self, forKey: .showSensitiveContent) ?? false
        requirePasswordForPurchases = try container.decodeIfPresent(Bool.self, forKey: .requirePasswordForPurchases) ?? true
        
        // Account changes
        lastUsernameChange = try container.decodeIfPresent(Date.self, forKey: .lastUsernameChange)
        lastDisplayNameChange = try container.decodeIfPresent(Date.self, forKey: .lastDisplayNameChange)
        pendingUsernameChange = try container.decodeIfPresent(String.self, forKey: .pendingUsernameChange)
        pendingDisplayNameChange = try container.decodeIfPresent(String.self, forKey: .pendingDisplayNameChange)
        usernameChangeRequestDate = try container.decodeIfPresent(Date.self, forKey: .usernameChangeRequestDate)
        displayNameChangeRequestDate = try container.decodeIfPresent(Date.self, forKey: .displayNameChangeRequestDate)
        
        // Onboarding
        interests = try container.decodeIfPresent([String].self, forKey: .interests)
        goals = try container.decodeIfPresent([String].self, forKey: .goals)
        preferredPrayerTime = try container.decodeIfPresent(String.self, forKey: .preferredPrayerTime)
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
    }
    
    init(
        id: String? = nil,
        email: String,
        displayName: String,
        username: String,
        initials: String? = nil,
        bio: String? = nil,
        profileImageURL: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        followersCount: Int = 0,
        followingCount: Int = 0,
        postsCount: Int = 0,
        isPrivate: Bool = false,
        notificationsEnabled: Bool = true,
        pushNotificationsEnabled: Bool = true,
        emailNotificationsEnabled: Bool = true,
        notifyOnLikes: Bool = true,
        notifyOnComments: Bool = true,
        notifyOnFollows: Bool = true,
        notifyOnMentions: Bool = true,
        notifyOnPrayerRequests: Bool = true,
        allowMessagesFromEveryone: Bool = true,
        showActivityStatus: Bool = true,
        allowTagging: Bool = true,
        showInterests: Bool = true,
        showSocialLinks: Bool = true,
        showBio: Bool = true,
        showFollowerCount: Bool = true,
        showFollowingCount: Bool = true,
        showSavedPosts: Bool = false,
        showReposts: Bool = true,
        loginAlerts: Bool = true,
        showSensitiveContent: Bool = false,
        requirePasswordForPurchases: Bool = true,
        lastUsernameChange: Date? = nil,
        lastDisplayNameChange: Date? = nil,
        pendingUsernameChange: String? = nil,
        pendingDisplayNameChange: String? = nil,
        usernameChangeRequestDate: Date? = nil,
        displayNameChangeRequestDate: Date? = nil,
        interests: [String]? = nil,
        goals: [String]? = nil,
        preferredPrayerTime: String? = nil,
        hasCompletedOnboarding: Bool = false
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.username = username
        self.initials = initials ?? String(displayName.prefix(2)).uppercased()
        self.bio = bio
        self.profileImageURL = profileImageURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.followersCount = followersCount
        self.followingCount = followingCount
        self.postsCount = postsCount
        self.isPrivate = isPrivate
        self.notificationsEnabled = notificationsEnabled
        self.pushNotificationsEnabled = pushNotificationsEnabled
        self.emailNotificationsEnabled = emailNotificationsEnabled
        self.notifyOnLikes = notifyOnLikes
        self.notifyOnComments = notifyOnComments
        self.notifyOnFollows = notifyOnFollows
        self.notifyOnMentions = notifyOnMentions
        self.notifyOnPrayerRequests = notifyOnPrayerRequests
        self.allowMessagesFromEveryone = allowMessagesFromEveryone
        self.showActivityStatus = showActivityStatus
        self.allowTagging = allowTagging
        self.showInterests = showInterests
        self.showSocialLinks = showSocialLinks
        self.showBio = showBio
        self.showFollowerCount = showFollowerCount
        self.showFollowingCount = showFollowingCount
        self.showSavedPosts = showSavedPosts
        self.showReposts = showReposts
        self.loginAlerts = loginAlerts
        self.showSensitiveContent = showSensitiveContent
        self.requirePasswordForPurchases = requirePasswordForPurchases
        self.lastUsernameChange = lastUsernameChange
        self.lastDisplayNameChange = lastDisplayNameChange
        self.pendingUsernameChange = pendingUsernameChange
        self.pendingDisplayNameChange = pendingDisplayNameChange
        self.usernameChangeRequestDate = usernameChangeRequestDate
        self.displayNameChangeRequestDate = displayNameChangeRequestDate
        self.interests = interests
        self.goals = goals
        self.preferredPrayerTime = preferredPrayerTime
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }
}

// MARK: - User Service

@MainActor
class UserService: ObservableObject {
    static let shared = UserService()
    
    @Published var currentUser: UserModel?
    @Published var isLoading = false
    @Published var error: String?
    
    private let firebaseManager = FirebaseManager.shared
    
    /// Fetch current user from Firestore
    func fetchCurrentUser() async {
        guard let userId = firebaseManager.currentUser?.uid else {
            error = "No authenticated user"
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let path = "\(FirebaseManager.CollectionPath.users)/\(userId)"
            currentUser = try await firebaseManager.fetchDocument(from: path, as: UserModel.self)
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    /// Fetch any user's profile by their Firebase user ID
    func fetchUserProfile(userId: String) async throws -> UserModel {
        print("👤 Fetching user profile for ID: \(userId)")
        
        let path = "\(FirebaseManager.CollectionPath.users)/\(userId)"
        
        do {
            let user = try await firebaseManager.fetchDocument(from: path, as: UserModel.self)
            print("✅ Successfully fetched user: \(user.displayName) (@\(user.username))")
            return user
        } catch {
            print("❌ Failed to fetch user profile: \(error)")
            throw error
        }
    }
    
    /// Create user profile in Firestore
    func createUserProfile(email: String, displayName: String, username: String) async throws {
        print("👤 UserService: Starting createUserProfile for \(username)")
        
        guard let userId = firebaseManager.currentUser?.uid else {
            print("❌ UserService: No authenticated user found!")
            throw FirebaseError.unauthorized
        }
        
        print("✅ UserService: User ID: \(userId)")
        
        // Validate username format (lowercase, alphanumeric + underscores, 3-20 chars)
        let cleanedUsername = username.lowercased().trimmingCharacters(in: .whitespaces)
        print("👤 UserService: Validating username: \(cleanedUsername)")
        
        guard isValidUsername(cleanedUsername) else {
            print("❌ UserService: Invalid username format")
            throw NSError(domain: "UserService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Username must be 3-20 characters (letters, numbers, underscores only)"])
        }
        
        print("✅ UserService: Username format is valid")
        
        // Check if username is available (skip if already checked in UI, but double-check for safety)
        print("👤 UserService: Checking username availability...")
        let isAvailable = try await isUsernameAvailable(cleanedUsername)
        
        guard isAvailable else {
            print("❌ UserService: Username '\(cleanedUsername)' is already taken")
            throw NSError(domain: "UserService", code: 409, userInfo: [NSLocalizedDescriptionKey: "Username '@\(cleanedUsername)' is already taken"])
        }
        
        print("✅ UserService: Username is available")
        
        let newUser = UserModel(
            id: userId,
            email: email,
            displayName: displayName,
            username: cleanedUsername
        )
        
        print("👤 UserService: Saving user to Firestore...")
        let path = "\(FirebaseManager.CollectionPath.users)/\(userId)"
        
        do {
            try await firebaseManager.saveDocument(newUser, to: path)
            print("✅ UserService: User profile saved successfully to \(path)")
            
            print("👤 UserService: Fetching current user...")
            await fetchCurrentUser()
            print("✅ UserService: createUserProfile completed successfully!")
        } catch {
            print("❌ UserService: Failed to save to Firestore: \(error)")
            throw error
        }
    }
    
    /// Validate username format
    private func isValidUsername(_ username: String) -> Bool {
        let usernameRegex = "^[a-z0-9_]{3,20}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", usernameRegex)
        return predicate.evaluate(with: username)
    }
    
    /// Check if username is available
    func isUsernameAvailable(_ username: String) async throws -> Bool {
        let db = Firestore.firestore()
        let query = db.collection(FirebaseManager.CollectionPath.users)
            .whereField("username", isEqualTo: username.lowercased())
            .limit(to: 1)
        
        let snapshot = try await query.getDocuments()
        return snapshot.documents.isEmpty
    }
    
    /// Update user profile
    func updateProfile(displayName: String? = nil, bio: String? = nil, profileImageURL: String? = nil) async throws {
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        var updates: [String: Any] = ["updatedAt": Date()]
        
        if let displayName = displayName {
            updates["displayName"] = displayName
            updates["initials"] = String(displayName.prefix(2)).uppercased()
        }
        
        if let bio = bio {
            updates["bio"] = bio
        }
        
        if let profileImageURL = profileImageURL {
            updates["profileImageURL"] = profileImageURL
        }
        
        let path = "\(FirebaseManager.CollectionPath.users)/\(userId)"
        try await firebaseManager.updateDocument(updates, at: path)
        
        await fetchCurrentUser()
    }
    
    /// Update user email in Firestore
    func updateUserEmail(newEmail: String) async throws {
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        let updates: [String: Any] = [
            "email": newEmail,
            "updatedAt": Date()
        ]
        
        let path = "\(FirebaseManager.CollectionPath.users)/\(userId)"
        try await firebaseManager.updateDocument(updates, at: path)
        
        await fetchCurrentUser()
    }
    
    /// Save onboarding preferences (interests, goals, prayer time, profile image)
    func saveOnboardingPreferences(
        interests: [String],
        goals: [String],
        prayerTime: String,
        profileImageURL: String? = nil
    ) async throws {
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        print("💾 Saving onboarding preferences to Firestore...")
        print("   - Interests: \(interests)")
        print("   - Goals: \(goals)")
        print("   - Prayer Time: \(prayerTime)")
        print("   - Profile Image URL: \(profileImageURL ?? "nil")")
        
        var updates: [String: Any] = [
            "interests": interests,
            "goals": goals,
            "preferredPrayerTime": prayerTime,
            "hasCompletedOnboarding": true,
            "updatedAt": Date()
        ]
        
        // Add profile image URL if provided
        if let profileImageURL = profileImageURL {
            updates["profileImageURL"] = profileImageURL
        }
        
        let path = "\(FirebaseManager.CollectionPath.users)/\(userId)"
        
        do {
            try await firebaseManager.updateDocument(updates, at: path)
            print("✅ Onboarding preferences saved successfully!")
            
            // Refresh current user data
            await fetchCurrentUser()
        } catch {
            print("❌ Failed to save onboarding preferences: \(error)")
            throw error
        }
    }
    
    /// Upload profile image
    func uploadProfileImage(_ image: UIImage) async throws -> String {
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        let path = "profile_images/\(userId)/profile.jpg"
        let url = try await firebaseManager.uploadImage(image, to: path)
        
        try await updateProfile(profileImageURL: url.absoluteString)
        
        return url.absoluteString
    }
    
    // MARK: - Username/DisplayName Change Requests
    
    /// Request username change (goes to pending approval)
    func requestUsernameChange(newUsername: String) async throws {
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        // Validate format
        guard isValidUsername(newUsername) else {
            throw NSError(domain: "UserService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid username format"])
        }
        
        // Check availability
        let available = try await isUsernameAvailable(newUsername)
        guard available else {
            throw NSError(domain: "UserService", code: 409, userInfo: [NSLocalizedDescriptionKey: "Username is already taken"])
        }
        
        // Check cooldown (30 days)
        if let lastChange = currentUser?.lastUsernameChange {
            let daysSince = Calendar.current.dateComponents([.day], from: lastChange, to: Date()).day ?? 0
            guard daysSince >= 30 else {
                throw NSError(domain: "UserService", code: 429, userInfo: [NSLocalizedDescriptionKey: "You can only change your username once every 30 days"])
            }
        }
        
        // Create pending request
        let updates: [String: Any] = [
            "pendingUsernameChange": newUsername,
            "usernameChangeRequestDate": Date(),
            "updatedAt": Date()
        ]
        
        let path = "\(FirebaseManager.CollectionPath.users)/\(userId)"
        try await firebaseManager.updateDocument(updates, at: path)
        
        print("✅ Username change request submitted: @\(newUsername)")
        
        await fetchCurrentUser()
    }
    
    /// Request display name change (goes to pending approval)
    func requestDisplayNameChange(newDisplayName: String) async throws {
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        guard !newDisplayName.isEmpty else {
            throw NSError(domain: "UserService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Display name cannot be empty"])
        }
        
        // Check cooldown (30 days)
        if let lastChange = currentUser?.lastDisplayNameChange {
            let daysSince = Calendar.current.dateComponents([.day], from: lastChange, to: Date()).day ?? 0
            guard daysSince >= 30 else {
                throw NSError(domain: "UserService", code: 429, userInfo: [NSLocalizedDescriptionKey: "You can only change your display name once every 30 days"])
            }
        }
        
        // Create pending request
        let updates: [String: Any] = [
            "pendingDisplayNameChange": newDisplayName,
            "displayNameChangeRequestDate": Date(),
            "updatedAt": Date()
        ]
        
        let path = "\(FirebaseManager.CollectionPath.users)/\(userId)"
        try await firebaseManager.updateDocument(updates, at: path)
        
        print("✅ Display name change request submitted: \(newDisplayName)")
        
        await fetchCurrentUser()
    }
    
    /// Update notification preferences
    func updateNotificationPreferences(
        pushEnabled: Bool? = nil,
        emailEnabled: Bool? = nil,
        notifyOnLikes: Bool? = nil,
        notifyOnComments: Bool? = nil,
        notifyOnFollows: Bool? = nil,
        notifyOnMentions: Bool? = nil,
        notifyOnPrayerRequests: Bool? = nil
    ) async throws {
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        var updates: [String: Any] = ["updatedAt": Date()]
        
        if let pushEnabled = pushEnabled {
            updates["pushNotificationsEnabled"] = pushEnabled
        }
        if let emailEnabled = emailEnabled {
            updates["emailNotificationsEnabled"] = emailEnabled
        }
        if let notifyOnLikes = notifyOnLikes {
            updates["notifyOnLikes"] = notifyOnLikes
        }
        if let notifyOnComments = notifyOnComments {
            updates["notifyOnComments"] = notifyOnComments
        }
        if let notifyOnFollows = notifyOnFollows {
            updates["notifyOnFollows"] = notifyOnFollows
        }
        if let notifyOnMentions = notifyOnMentions {
            updates["notifyOnMentions"] = notifyOnMentions
        }
        if let notifyOnPrayerRequests = notifyOnPrayerRequests {
            updates["notifyOnPrayerRequests"] = notifyOnPrayerRequests
        }
        
        let path = "\(FirebaseManager.CollectionPath.users)/\(userId)"
        try await firebaseManager.updateDocument(updates, at: path)
        
        await fetchCurrentUser()
    }
    
    /// Update privacy settings
    func updatePrivacySettings(
        isPrivate: Bool? = nil,
        allowMessagesFromEveryone: Bool? = nil,
        showActivityStatus: Bool? = nil,
        allowTagging: Bool? = nil
    ) async throws {
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        var updates: [String: Any] = ["updatedAt": Date()]
        
        if let isPrivate = isPrivate {
            updates["isPrivate"] = isPrivate
        }
        if let allowMessagesFromEveryone = allowMessagesFromEveryone {
            updates["allowMessagesFromEveryone"] = allowMessagesFromEveryone
        }
        if let showActivityStatus = showActivityStatus {
            updates["showActivityStatus"] = showActivityStatus
        }
        if let allowTagging = allowTagging {
            updates["allowTagging"] = allowTagging
        }
        
        let path = "\(FirebaseManager.CollectionPath.users)/\(userId)"
        try await firebaseManager.updateDocument(updates, at: path)
        
        await fetchCurrentUser()
    }
    
    /// Update profile visibility settings
    func updateProfileVisibility(
        showInterests: Bool,
        showSocialLinks: Bool,
        showBio: Bool,
        showFollowerCount: Bool,
        showFollowingCount: Bool,
        showSavedPosts: Bool,
        showReposts: Bool
    ) async throws {
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        let updates: [String: Any] = [
            "showInterests": showInterests,
            "showSocialLinks": showSocialLinks,
            "showBio": showBio,
            "showFollowerCount": showFollowerCount,
            "showFollowingCount": showFollowingCount,
            "showSavedPosts": showSavedPosts,
            "showReposts": showReposts,
            "updatedAt": Date()
        ]
        
        let path = "\(FirebaseManager.CollectionPath.users)/\(userId)"
        try await firebaseManager.updateDocument(updates, at: path)
        
        await fetchCurrentUser()
    }
    
    /// Update security settings (login alerts, content filtering)
    func updateSecuritySettings(
        loginAlerts: Bool? = nil,
        showSensitiveContent: Bool? = nil,
        requirePasswordForPurchases: Bool? = nil
    ) async throws {
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        var updates: [String: Any] = ["updatedAt": Date()]
        
        if let loginAlerts = loginAlerts {
            updates["loginAlerts"] = loginAlerts
        }
        if let showSensitiveContent = showSensitiveContent {
            updates["showSensitiveContent"] = showSensitiveContent
        }
        if let requirePasswordForPurchases = requirePasswordForPurchases {
            updates["requirePasswordForPurchases"] = requirePasswordForPurchases
        }
        
        let path = "\(FirebaseManager.CollectionPath.users)/\(userId)"
        try await firebaseManager.updateDocument(updates, at: path)
        
        print("✅ Security settings updated")
        await fetchCurrentUser()
    }
}

