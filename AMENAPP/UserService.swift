//
//  UserService.swift
//  AMENAPP
//
//  Service for managing user profile data and operations
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Combine
import UIKit

// MARK: - User Service Errors

enum UserServiceError: LocalizedError {
    case unauthorized
    case documentNotFound
    case imageCompressionFailed
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "You must be signed in to perform this action."
        case .documentNotFound:
            return "The requested user profile was not found."
        case .imageCompressionFailed:
            return "Failed to compress the profile image."
        case .invalidData:
            return "The user data is invalid or incomplete."
        }
    }
}

// MARK: - User Model

struct User: Codable, Identifiable {
    var id: String // Firebase Auth UID (set manually after decoding)
    var email: String
    var displayName: String
    var displayNameLowercase: String
    var username: String
    var usernameLowercase: String
    var initials: String
    var bio: String
    var profileImageURL: String?
    var nameKeywords: [String]
    
    // Profile Information
    var interests: [String]
    var goals: [String]
    var preferredPrayerTime: String
    
    // Social Links
    var socialLinks: [[String: String]]
    
    // Stats
    var followersCount: Int
    var followingCount: Int
    var postsCount: Int
    
    // Settings
    var isPrivate: Bool
    var notificationsEnabled: Bool
    var pushNotificationsEnabled: Bool
    var emailNotificationsEnabled: Bool
    var notifyOnLikes: Bool
    var notifyOnComments: Bool
    var notifyOnFollows: Bool
    var notifyOnMentions: Bool
    var notifyOnPrayerRequests: Bool
    var allowMessagesFromEveryone: Bool
    var showActivityStatus: Bool
    var allowTagging: Bool
    
    // Security Settings
    var loginAlerts: Bool
    var showSensitiveContent: Bool
    var requirePasswordForPurchases: Bool
    
    // Metadata
    var createdAt: Date
    var updatedAt: Date
    var hasCompletedOnboarding: Bool
    
    enum CodingKeys: String, CodingKey {
        // NOTE: 'id' is intentionally excluded from CodingKeys
        // It's set manually from the document ID after decoding
        case email
        case displayName
        case displayNameLowercase
        case username
        case usernameLowercase
        case initials
        case bio
        case profileImageURL
        case nameKeywords
        case interests
        case goals
        case preferredPrayerTime
        case socialLinks
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
        case loginAlerts
        case showSensitiveContent
        case requirePasswordForPurchases
        case createdAt
        case updatedAt
        case hasCompletedOnboarding
    }
    
    // Custom decoder that handles missing 'id' field
    // The 'id' should be set manually from the document ID after decoding
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // IMPORTANT: id is NOT decoded from Firestore data
        // It must be set manually from the document ID
        id = "" // Temporary value, will be set by caller
        
        email = try container.decode(String.self, forKey: .email)
        displayName = try container.decode(String.self, forKey: .displayName)
        displayNameLowercase = try container.decodeIfPresent(String.self, forKey: .displayNameLowercase) ?? displayName.lowercased()
        username = try container.decode(String.self, forKey: .username)
        usernameLowercase = try container.decodeIfPresent(String.self, forKey: .usernameLowercase) ?? username.lowercased()
        initials = try container.decode(String.self, forKey: .initials)
        bio = try container.decodeIfPresent(String.self, forKey: .bio) ?? ""
        profileImageURL = try container.decodeIfPresent(String.self, forKey: .profileImageURL)
        nameKeywords = try container.decodeIfPresent([String].self, forKey: .nameKeywords) ?? []
        
        interests = try container.decodeIfPresent([String].self, forKey: .interests) ?? []
        goals = try container.decodeIfPresent([String].self, forKey: .goals) ?? []
        preferredPrayerTime = try container.decodeIfPresent(String.self, forKey: .preferredPrayerTime) ?? "Morning"
        
        socialLinks = try container.decodeIfPresent([[String: String]].self, forKey: .socialLinks) ?? []
        
        followersCount = try container.decodeIfPresent(Int.self, forKey: .followersCount) ?? 0
        followingCount = try container.decodeIfPresent(Int.self, forKey: .followingCount) ?? 0
        postsCount = try container.decodeIfPresent(Int.self, forKey: .postsCount) ?? 0
        
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
        
        loginAlerts = try container.decodeIfPresent(Bool.self, forKey: .loginAlerts) ?? true
        showSensitiveContent = try container.decodeIfPresent(Bool.self, forKey: .showSensitiveContent) ?? false
        requirePasswordForPurchases = try container.decodeIfPresent(Bool.self, forKey: .requirePasswordForPurchases) ?? true
        
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        // NOTE: 'id' is NOT encoded - it's stored as the document ID in Firestore
        try container.encode(email, forKey: .email)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(displayNameLowercase, forKey: .displayNameLowercase)
        try container.encode(username, forKey: .username)
        try container.encode(usernameLowercase, forKey: .usernameLowercase)
        try container.encode(initials, forKey: .initials)
        try container.encode(bio, forKey: .bio)
        try container.encodeIfPresent(profileImageURL, forKey: .profileImageURL)
        try container.encode(nameKeywords, forKey: .nameKeywords)
        try container.encode(interests, forKey: .interests)
        try container.encode(goals, forKey: .goals)
        try container.encode(preferredPrayerTime, forKey: .preferredPrayerTime)
        try container.encode(socialLinks, forKey: .socialLinks)
        try container.encode(followersCount, forKey: .followersCount)
        try container.encode(followingCount, forKey: .followingCount)
        try container.encode(postsCount, forKey: .postsCount)
        try container.encode(isPrivate, forKey: .isPrivate)
        try container.encode(notificationsEnabled, forKey: .notificationsEnabled)
        try container.encode(pushNotificationsEnabled, forKey: .pushNotificationsEnabled)
        try container.encode(emailNotificationsEnabled, forKey: .emailNotificationsEnabled)
        try container.encode(notifyOnLikes, forKey: .notifyOnLikes)
        try container.encode(notifyOnComments, forKey: .notifyOnComments)
        try container.encode(notifyOnFollows, forKey: .notifyOnFollows)
        try container.encode(notifyOnMentions, forKey: .notifyOnMentions)
        try container.encode(notifyOnPrayerRequests, forKey: .notifyOnPrayerRequests)
        try container.encode(allowMessagesFromEveryone, forKey: .allowMessagesFromEveryone)
        try container.encode(showActivityStatus, forKey: .showActivityStatus)
        try container.encode(allowTagging, forKey: .allowTagging)
        try container.encode(loginAlerts, forKey: .loginAlerts)
        try container.encode(showSensitiveContent, forKey: .showSensitiveContent)
        try container.encode(requirePasswordForPurchases, forKey: .requirePasswordForPurchases)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(hasCompletedOnboarding, forKey: .hasCompletedOnboarding)
    }
}

// MARK: - Legacy User Service (deprecated - use UserService from UserModel.swift)

@MainActor
class LegacyUserService: ObservableObject {
    static let shared = LegacyUserService()
    
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var error: String?
    
    private let db = Firestore.firestore()
    private let firebaseManager = FirebaseManager.shared
    private let storage = Storage.storage()
    
    private var userListener: ListenerRegistration?
    
    init() {
        print("👤 UserService initialized")
    }
    
    deinit {
        userListener?.remove()
    }
    
    // MARK: - Fetch Current User
    
    /// Fetch the current authenticated user's profile data from Firestore
    func fetchCurrentUser() async {
        guard let userId = firebaseManager.currentUser?.uid else {
            print("❌ UserService: No authenticated user")
            return
        }
        
        print("📥 UserService: Fetching user profile for ID: \(userId)")
        isLoading = true
        
        do {
            let document = try await db.collection("users").document(userId).getDocument()
            
            guard document.exists else {
                print("❌ UserService: User document not found")
                error = "User profile not found"
                isLoading = false
                return
            }
            
            // Decode user data
            var userData = try document.data(as: User.self)
            userData.id = userId // Ensure ID is set
            
            currentUser = userData
            
            // ✅ Cache user data to UserDefaults for offline access and post creation
            UserDefaults.standard.set(userData.displayName, forKey: "currentUserDisplayName")
            UserDefaults.standard.set(userData.username, forKey: "currentUserUsername")
            UserDefaults.standard.set(userData.initials, forKey: "currentUserInitials")
            if let profileImageURL = userData.profileImageURL {
                UserDefaults.standard.set(profileImageURL, forKey: "currentUserProfileImageURL")
                print("   ✅ Cached profile image URL: \(profileImageURL)")
            } else {
                // Clear cached URL if user removed their profile photo
                UserDefaults.standard.removeObject(forKey: "currentUserProfileImageURL")
            }
            
            print("✅ UserService: User profile loaded successfully")
            print("   Name: \(userData.displayName)")
            print("   Username: @\(userData.username)")
            print("   Bio: \(userData.bio)")
            print("   Interests: \(userData.interests)")
            print("   Profile Image: \(userData.profileImageURL ?? "none")")
            
            isLoading = false
            
        } catch {
            print("❌ UserService: Failed to fetch user - \(error)")
            self.error = error.localizedDescription
            isLoading = false
        }
    }
    
    // MARK: - Start Real-time Listener
    
    /// Start listening to user profile changes in real-time
    func startListeningToCurrentUser() {
        guard let userId = firebaseManager.currentUser?.uid else {
            print("❌ UserService: Cannot start listener - no user")
            return
        }
        
        print("👂 UserService: Starting real-time listener for user: \(userId)")
        
        userListener = db.collection("users").document(userId).addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ UserService: Listener error - \(error)")
                Task { @MainActor in
                    self.error = error.localizedDescription
                }
                return
            }
            
            guard let snapshot = snapshot, snapshot.exists else {
                print("❌ UserService: User document doesn't exist")
                return
            }
            
            do {
                var userData = try snapshot.data(as: User.self)
                userData.id = userId
                
                Task { @MainActor in
                    self.currentUser = userData
                    
                    // ✅ Update cached user data in UserDefaults when profile changes
                    UserDefaults.standard.set(userData.displayName, forKey: "currentUserDisplayName")
                    UserDefaults.standard.set(userData.username, forKey: "currentUserUsername")
                    UserDefaults.standard.set(userData.initials, forKey: "currentUserInitials")
                    if let profileImageURL = userData.profileImageURL {
                        UserDefaults.standard.set(profileImageURL, forKey: "currentUserProfileImageURL")
                        print("   ✅ Updated cached profile image URL: \(profileImageURL)")
                    } else {
                        UserDefaults.standard.removeObject(forKey: "currentUserProfileImageURL")
                    }
                    
                    print("🔄 UserService: User profile updated via listener")
                }
            } catch {
                print("❌ UserService: Failed to decode user - \(error)")
            }
        }
    }
    
    /// Stop listening to user profile changes
    func stopListening() {
        userListener?.remove()
        userListener = nil
        print("🔇 UserService: Stopped real-time listener")
    }
    
    // MARK: - Update Profile
    
    /// Update user's display name and bio
    func updateProfile(displayName: String, bio: String) async throws {
        guard let userId = firebaseManager.currentUser?.uid else {
            throw UserServiceError.unauthorized
        }
        
        print("💾 UserService: Updating profile...")
        print("   Name: \(displayName)")
        print("   Bio: \(bio)")
        
        // Generate new initials
        let names = displayName.components(separatedBy: " ")
        let firstName = names.first ?? ""
        let lastName = names.count > 1 ? names.last ?? "" : ""
        let initials = "\(firstName.prefix(1))\(lastName.prefix(1))".uppercased()
        
        // Generate name keywords for search
        let nameKeywords = createNameKeywords(from: displayName)
        
        let updateData: [String: Any] = [
            "displayName": displayName,
            "displayNameLowercase": displayName.lowercased(),
            "initials": initials,
            "bio": bio,
            "nameKeywords": nameKeywords,
            "updatedAt": Timestamp(date: Date())
        ]
        
        try await db.collection("users").document(userId).updateData(updateData)
        
        print("✅ UserService: Profile updated successfully")
        
        // Update local cache
        if var user = currentUser {
            user.displayName = displayName
            user.displayNameLowercase = displayName.lowercased()
            user.initials = initials
            user.bio = bio
            user.nameKeywords = nameKeywords
            user.updatedAt = Date()
            currentUser = user
        }
        
        // Update cached data for post creation
        UserDefaults.standard.set(displayName, forKey: "currentUserDisplayName")
        UserDefaults.standard.set(initials, forKey: "currentUserInitials")
        
        // Sync to Algolia for search
        try? await AlgoliaSyncService.shared.syncUser(userId: userId, userData: updateData)
    }
    
    // MARK: - Upload Profile Image
    
    /// Upload profile image to Firebase Storage and update Firestore
    func uploadProfileImage(_ image: UIImage, compressionQuality: CGFloat = 0.7) async throws -> String {
        guard let userId = firebaseManager.currentUser?.uid else {
            throw UserServiceError.unauthorized
        }
        
        print("📤 UserService: Uploading profile image...")
        
        // Compress image
        guard let imageData = image.jpegData(compressionQuality: compressionQuality) else {
            throw UserServiceError.imageCompressionFailed
        }
        
        // Upload to Storage
        let path = "profile_images/\(userId)/profile.jpg"
        let storageRef = storage.reference().child(path)
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        _ = try await storageRef.putDataAsync(imageData, metadata: metadata)
        let downloadURL = try await storageRef.downloadURL()
        
        print("✅ UserService: Image uploaded to: \(downloadURL.absoluteString)")
        
        // Update Firestore with new URL
        let updateData: [String: Any] = [
            "profileImageURL": downloadURL.absoluteString,
            "updatedAt": Timestamp(date: Date())
        ]
        
        try await db.collection("users").document(userId).updateData(updateData)
        
        print("✅ UserService: Profile image URL updated in Firestore")
        
        // Update profile photos in all conversations
        await updateProfilePhotoInConversations(userId: userId, photoURL: downloadURL.absoluteString)
        
        // Update local cache
        if var user = currentUser {
            user.profileImageURL = downloadURL.absoluteString
            user.updatedAt = Date()
            currentUser = user
        }
        
        // Cache for post creation
        UserDefaults.standard.set(downloadURL.absoluteString, forKey: "currentUserProfileImageURL")
        
        return downloadURL.absoluteString
    }
    
    /// Update profile image URL in Firestore (without uploading)
    func updateProfileImage(_ imageURL: String) async throws {
        guard let userId = firebaseManager.currentUser?.uid else {
            throw UserServiceError.unauthorized
        }
        
        print("💾 UserService: Updating profile image URL...")
        
        let updateData: [String: Any] = [
            "profileImageURL": imageURL,
            "updatedAt": Timestamp(date: Date())
        ]
        
        try await db.collection("users").document(userId).updateData(updateData)
        
        print("✅ UserService: Profile image URL updated")
        
        // Update profile photos in all conversations
        await updateProfilePhotoInConversations(userId: userId, photoURL: imageURL)
        
        // Update local cache
        if var user = currentUser {
            user.profileImageURL = imageURL
            user.updatedAt = Date()
            currentUser = user
        }
        
        UserDefaults.standard.set(imageURL, forKey: "currentUserProfileImageURL")
    }
    
    // MARK: - Remove Profile Image
    
    /// Remove profile image from Storage and Firestore
    func removeProfileImage() async throws {
        guard let userId = firebaseManager.currentUser?.uid else {
            throw UserServiceError.unauthorized
        }
        
        print("🗑️ UserService: Removing profile image...")
        
        // Remove from Firestore (set to null)
        let updateData: [String: Any] = [
            "profileImageURL": NSNull(),
            "updatedAt": Timestamp(date: Date())
        ]
        
        try await db.collection("users").document(userId).updateData(updateData)
        
        // Update profile photos in all conversations (set to empty)
        await updateProfilePhotoInConversations(userId: userId, photoURL: "")
        
        // Try to delete from Storage (non-critical if fails)
        let path = "profile_images/\(userId)/profile.jpg"
        let storageRef = storage.reference().child(path)
        
        try? await storageRef.delete()
        
        print("✅ UserService: Profile image removed")
        
        // Update local cache
        if var user = currentUser {
            user.profileImageURL = nil
            user.updatedAt = Date()
            currentUser = user
        }
        
        UserDefaults.standard.removeObject(forKey: "currentUserProfileImageURL")
    }
    
    // MARK: - Update Interests & Preferences
    
    /// Save onboarding preferences (interests, goals, prayer time)
    func saveOnboardingPreferences(interests: [String], goals: [String], prayerTime: String) async throws {
        guard let userId = firebaseManager.currentUser?.uid else {
            throw UserServiceError.unauthorized
        }
        
        print("💾 UserService: Saving onboarding preferences...")
        print("   Interests: \(interests)")
        print("   Goals: \(goals)")
        print("   Prayer Time: \(prayerTime)")
        
        let updateData: [String: Any] = [
            "interests": interests,
            "goals": goals,
            "preferredPrayerTime": prayerTime,
            "hasCompletedOnboarding": true,
            "updatedAt": Timestamp(date: Date())
        ]
        
        // Use setData with merge to create document if it doesn't exist
        try await db.collection("users").document(userId).setData(updateData, merge: true)
        
        print("✅ UserService: Preferences saved successfully")
        
        // Update local cache
        if var user = currentUser {
            user.interests = interests
            user.goals = goals
            user.preferredPrayerTime = prayerTime
            user.hasCompletedOnboarding = true
            user.updatedAt = Date()
            currentUser = user
        }
    }
    
    // MARK: - Update Security Settings
    
    /// Update security and privacy settings
    func updateSecuritySettings(
        loginAlerts: Bool,
        showSensitiveContent: Bool,
        requirePasswordForPurchases: Bool
    ) async throws {
        guard let userId = firebaseManager.currentUser?.uid else {
            throw UserServiceError.unauthorized
        }
        
        print("🔒 UserService: Updating security settings...")
        
        let updateData: [String: Any] = [
            "loginAlerts": loginAlerts,
            "showSensitiveContent": showSensitiveContent,
            "requirePasswordForPurchases": requirePasswordForPurchases,
            "updatedAt": Timestamp(date: Date())
        ]
        
        try await db.collection("users").document(userId).updateData(updateData)
        
        print("✅ UserService: Security settings updated")
        
        // Update local cache
        if var user = currentUser {
            user.loginAlerts = loginAlerts
            user.showSensitiveContent = showSensitiveContent
            user.requirePasswordForPurchases = requirePasswordForPurchases
            user.updatedAt = Date()
            currentUser = user
        }
    }
    
    // MARK: - Update Notification Settings
    
    /// Update notification preferences
    func updateNotificationSettings(
        pushEnabled: Bool,
        emailEnabled: Bool,
        notifyOnLikes: Bool,
        notifyOnComments: Bool,
        notifyOnFollows: Bool,
        notifyOnMentions: Bool,
        notifyOnPrayerRequests: Bool
    ) async throws {
        guard let userId = firebaseManager.currentUser?.uid else {
            throw UserServiceError.unauthorized
        }
        
        print("🔔 UserService: Updating notification settings...")
        
        let updateData: [String: Any] = [
            "pushNotificationsEnabled": pushEnabled,
            "emailNotificationsEnabled": emailEnabled,
            "notifyOnLikes": notifyOnLikes,
            "notifyOnComments": notifyOnComments,
            "notifyOnFollows": notifyOnFollows,
            "notifyOnMentions": notifyOnMentions,
            "notifyOnPrayerRequests": notifyOnPrayerRequests,
            "updatedAt": Timestamp(date: Date())
        ]
        
        try await db.collection("users").document(userId).updateData(updateData)
        
        print("✅ UserService: Notification settings updated")
        
        // Update local cache
        if var user = currentUser {
            user.pushNotificationsEnabled = pushEnabled
            user.emailNotificationsEnabled = emailEnabled
            user.notifyOnLikes = notifyOnLikes
            user.notifyOnComments = notifyOnComments
            user.notifyOnFollows = notifyOnFollows
            user.notifyOnMentions = notifyOnMentions
            user.notifyOnPrayerRequests = notifyOnPrayerRequests
            user.updatedAt = Date()
            currentUser = user
        }
    }
    
    // MARK: - Fetch Other User
    
    /// Fetch any user's profile by ID
    func fetchUser(userId: String) async throws -> User {
        print("📥 UserService: Fetching user profile for ID: \(userId)")
        
        let document = try await db.collection("users").document(userId).getDocument()
        
        guard document.exists else {
            throw UserServiceError.documentNotFound
        }
        
        var userData = try document.data(as: User.self)
        userData.id = userId
        
        print("✅ UserService: User profile loaded: \(userData.displayName)")
        
        return userData
    }
    
    // MARK: - Search Users
    
    /// Search users by name or username
    func searchUsers(query: String, limit: Int = 20) async throws -> [User] {
        print("🔍 UserService: Searching users with query: \(query)")
        
        let lowercaseQuery = query.lowercased()
        
        // Search by display name
        let nameResults = try await db.collection("users")
            .whereField("displayNameLowercase", isGreaterThanOrEqualTo: lowercaseQuery)
            .whereField("displayNameLowercase", isLessThan: lowercaseQuery + "\u{f8ff}")
            .limit(to: limit)
            .getDocuments()
        
        // Search by username
        let usernameResults = try await db.collection("users")
            .whereField("usernameLowercase", isGreaterThanOrEqualTo: lowercaseQuery)
            .whereField("usernameLowercase", isLessThan: lowercaseQuery + "\u{f8ff}")
            .limit(to: limit)
            .getDocuments()
        
        // Combine and deduplicate results
        var users: [User] = []
        var userIds = Set<String>()
        
        for doc in nameResults.documents + usernameResults.documents {
            let userId = doc.documentID
            if !userIds.contains(userId) {
                var user = try doc.data(as: User.self)
                user.id = userId
                users.append(user)
                userIds.insert(userId)
            }
        }
        
        print("✅ UserService: Found \(users.count) users")
        
        return users
    }
    
    // MARK: - Helper Methods
    
    /// Update profile photo in all conversations the user is part of
    private func updateProfilePhotoInConversations(userId: String, photoURL: String) async {
        do {
            print("🔄 Updating profile photo in conversations for user: \(userId)")
            
            // Find all conversations where user is a participant
            let conversationsSnapshot = try await db.collection("conversations")
                .whereField("participantIds", arrayContains: userId)
                .getDocuments()
            
            print("📝 Found \(conversationsSnapshot.documents.count) conversations to update")
            
            // Update each conversation's participantPhotoURLs map
            for document in conversationsSnapshot.documents {
                let conversationRef = db.collection("conversations").document(document.documentID)
                
                try await conversationRef.updateData([
                    "participantPhotoURLs.\(userId)": photoURL,
                    "updatedAt": Timestamp(date: Date())
                ])
                
                print("✅ Updated profile photo in conversation: \(document.documentID)")
            }
            
            print("🎉 Profile photo updated in all conversations")
        } catch {
            print("❌ Error updating profile photo in conversations: \(error)")
        }
    }
    
    /// Generate searchable keywords from name
    private func createNameKeywords(from displayName: String) -> [String] {
        var keywords: [String] = []
        let lowercasedName = displayName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Add full name
        keywords.append(lowercasedName)
        
        // Add individual words
        let words = lowercasedName.components(separatedBy: " ").filter { !$0.isEmpty }
        keywords.append(contentsOf: words)
        
        // Add first name + last name combinations
        if words.count >= 2 {
            let firstName = words[0]
            let lastName = words[words.count - 1]
            keywords.append("\(firstName) \(lastName)")
        }
        
        // Remove duplicates
        return Array(Set(keywords))
    }
}


