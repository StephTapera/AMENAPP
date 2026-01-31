//
//  FirebaseManager.swift
//  AMENAPP
//
//  Created by Steph on 1/19/26.
//

import Foundation
import UIKit
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import GoogleSignIn
import AuthenticationServices
import CryptoKit

/// Centralized Firebase manager for handling all Firebase operations
class FirebaseManager {
    static let shared = FirebaseManager()
    
    let auth: Auth
    let firestore: Firestore
    let storage: Storage
    
    private init() {
        self.auth = Auth.auth()
        self.firestore = Firestore.firestore()
        self.storage = Storage.storage()
    }
    
    // MARK: - Collection Paths
    
    enum CollectionPath {
        static let users = "users"
        static let posts = "posts"
        static let testimonies = "testimonies"
        static let prayers = "prayers"
        static let comments = "comments"
        static let messages = "messages"
        static let notifications = "notifications"
        static let communities = "communities"  // Community/Groups
        static let savedPosts = "savedPosts"  // User's saved posts
        static let reposts = "reposts"  // Repost tracking
        
        static func userPosts(userId: String) -> String {
            "\(users)/\(userId)/posts"
        }
        
        static func postComments(postId: String) -> String {
            "\(posts)/\(postId)/comments"
        }
        
        static func userFollowers(userId: String) -> String {
            "follows"  // Query where followingId == userId
        }
        
        static func userFollowing(userId: String) -> String {
            "follows"  // Query where followerId == userId
        }
    }
    
    // MARK: - Authentication
    
    /// Current authenticated user (Firebase Auth User)
    var currentUser: FirebaseAuth.User? {
        auth.currentUser
    }
    
    /// Check if user is authenticated
    var isAuthenticated: Bool {
        currentUser != nil
    }
    
    /// Sign in with email and password
    func signIn(email: String, password: String) async throws -> FirebaseAuth.User {
        let result = try await auth.signIn(withEmail: email, password: password)
        return result.user
    }
    
    /// Sign up with email and password
    func signUp(email: String, password: String, displayName: String, username: String? = nil) async throws -> FirebaseAuth.User {
        print("🔐 FirebaseManager: Creating new user account...")
        
        // Create Firebase Auth user
        let result = try await auth.createUser(withEmail: email, password: password)
        let user = result.user
        
        print("✅ FirebaseManager: Auth user created with ID: \(user.uid)")
        
        // Use provided username or extract from email (before @)
        let finalUsername = username?.lowercased() ?? email.components(separatedBy: "@").first?.lowercased() ?? "user"
        
        // Create initials from display name
        let names = displayName.components(separatedBy: " ")
        let firstName = names.first ?? ""
        let lastName = names.count > 1 ? names.last ?? "" : ""
        let initials = "\(firstName.prefix(1))\(lastName.prefix(1))".uppercased()
        
        // Create searchable name keywords for messaging search
        let nameKeywords = createNameKeywords(from: displayName)
        
        print("📝 FirebaseManager: Creating user profile...")
        print("   - Display Name: \(displayName)")
        print("   - Username: \(finalUsername)")
        print("   - Initials: \(initials)")
        print("   - Name Keywords: \(nameKeywords)")
        
        // Create user profile in Firestore
        let userData: [String: Any] = [
            "email": email,
            "displayName": displayName,
            "displayNameLowercase": displayName.lowercased(),
            "username": finalUsername,
            "usernameLowercase": finalUsername,
            "initials": initials,
            "bio": "",
            "profileImageURL": NSNull(),
            "nameKeywords": nameKeywords, // For search functionality
            "createdAt": Timestamp(date: Date()),
            "updatedAt": Timestamp(date: Date()),
            "followersCount": 0,
            "followingCount": 0,
            "postsCount": 0,
            "isPrivate": false,
            "notificationsEnabled": true,
            "pushNotificationsEnabled": true,
            "emailNotificationsEnabled": true,
            "notifyOnLikes": true,
            "notifyOnComments": true,
            "notifyOnFollows": true,
            "notifyOnMentions": true,
            "notifyOnPrayerRequests": true,
            "allowMessagesFromEveryone": true,
            "showActivityStatus": true,
            "allowTagging": true,
            "hasCompletedOnboarding": false
        ]
        
        do {
            try await firestore.collection(CollectionPath.users)
                .document(user.uid)
                .setData(userData)
            
            print("✅ FirebaseManager: User profile created successfully!")
            
            // ⭐️ Sync to Algolia for instant search
            do {
                try await AlgoliaSyncService.shared.syncUser(userId: user.uid, userData: userData)
                print("✅ FirebaseManager: User synced to Algolia")
            } catch {
                print("⚠️ FirebaseManager: Algolia sync failed (non-critical): \(error)")
                // Don't throw - user creation succeeded, search sync is optional
            }
            
            print("🎉 Complete user setup finished for: \(displayName)")
            
        } catch {
            print("❌ FirebaseManager: Failed to create user profile: \(error)")
            // Delete the auth user if profile creation fails
            try? await user.delete()
            throw error
        }
        
        return user
    }
    
    /// Sign out current user
    func signOut() throws {
        try auth.signOut()
    }
    
    /// Send password reset email
    func sendPasswordReset(email: String) async throws {
        try await auth.sendPasswordReset(withEmail: email)
    }
    
    // MARK: - Google Sign-In
    
    /// Sign in with Google
    @MainActor
    func signInWithGoogle() async throws -> FirebaseAuth.User {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw FirebaseError.invalidData
        }
        
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            throw FirebaseError.unauthorized
        }
        
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
        let user = result.user
        
        guard let idToken = user.idToken?.tokenString else {
            throw FirebaseError.invalidData
        }
        
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: user.accessToken.tokenString
        )
        
        let authResult = try await auth.signIn(with: credential)
        
        // Check if this is a new user and create profile if needed
        if authResult.additionalUserInfo?.isNewUser == true {
            try await createGoogleUserProfile(user: authResult.user, googleUser: user)
        }
        
        return authResult.user
    }
    
    /// Create user profile for Google Sign-In
    private func createGoogleUserProfile(user: FirebaseAuth.User, googleUser: GIDGoogleUser) async throws {
        let displayName = user.displayName ?? googleUser.profile?.name ?? "User"
        let email = user.email ?? googleUser.profile?.email ?? ""
        
        // Generate username from email
        let username = email.components(separatedBy: "@").first?.lowercased() ?? "user\(Int.random(in: 1000...9999))"
        
        // Create initials
        let names = displayName.components(separatedBy: " ")
        let firstName = names.first ?? ""
        let lastName = names.count > 1 ? names.last ?? "" : ""
        let initials = "\(firstName.prefix(1))\(lastName.prefix(1))".uppercased()
        
        // Create searchable keywords
        let nameKeywords = createNameKeywords(from: displayName)
        
        let userData: [String: Any] = [
            "email": email,
            "displayName": displayName,
            "displayNameLowercase": displayName.lowercased(),
            "username": username,
            "usernameLowercase": username,
            "initials": initials,
            "bio": "",
            "profileImageURL": user.photoURL?.absoluteString ?? NSNull(),
            "nameKeywords": nameKeywords,
            "createdAt": Timestamp(date: Date()),
            "updatedAt": Timestamp(date: Date()),
            "followersCount": 0,
            "followingCount": 0,
            "postsCount": 0,
            "isPrivate": false,
            "notificationsEnabled": true,
            "pushNotificationsEnabled": true,
            "emailNotificationsEnabled": true,
            "notifyOnLikes": true,
            "notifyOnComments": true,
            "notifyOnFollows": true,
            "notifyOnMentions": true,
            "notifyOnPrayerRequests": true,
            "allowMessagesFromEveryone": true,
            "showActivityStatus": true,
            "allowTagging": true,
            "hasCompletedOnboarding": false,
            "authProvider": "google"
        ]
        
        try await firestore.collection(CollectionPath.users)
            .document(user.uid)
            .setData(userData)
        
        // Sync to Algolia
        try? await AlgoliaSyncService.shared.syncUser(userId: user.uid, userData: userData)
    }
    
    // MARK: - Apple Sign-In
    
    /// Sign in with Apple
    func signInWithApple(idToken: String, nonce: String, fullName: PersonNameComponents?) async throws -> FirebaseAuth.User {
        let credential = OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: nonce,
            fullName: fullName
        )
        
        let authResult = try await auth.signIn(with: credential)
        
        // Check if this is a new user and create profile if needed
        if authResult.additionalUserInfo?.isNewUser == true {
            try await createAppleUserProfile(user: authResult.user, fullName: fullName)
        }
        
        return authResult.user
    }
    
    /// Create user profile for Apple Sign-In
    private func createAppleUserProfile(user: FirebaseAuth.User, fullName: PersonNameComponents?) async throws {
        // Apple provides full name only on first sign-in
        let firstName = fullName?.givenName ?? "User"
        let lastName = fullName?.familyName ?? ""
        let displayName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        let email = user.email ?? "user@privaterelay.appleid.com"
        
        // Generate username
        let username = email.components(separatedBy: "@").first?.lowercased() ?? "user\(Int.random(in: 1000...9999))"
        
        // Create initials
        let initials = "\(firstName.prefix(1))\(lastName.prefix(1))".uppercased()
        
        // Create searchable keywords
        let nameKeywords = createNameKeywords(from: displayName)
        
        let userData: [String: Any] = [
            "email": email,
            "displayName": displayName,
            "displayNameLowercase": displayName.lowercased(),
            "username": username,
            "usernameLowercase": username,
            "initials": initials,
            "bio": "",
            "profileImageURL": NSNull(),
            "nameKeywords": nameKeywords,
            "createdAt": Timestamp(date: Date()),
            "updatedAt": Timestamp(date: Date()),
            "followersCount": 0,
            "followingCount": 0,
            "postsCount": 0,
            "isPrivate": false,
            "notificationsEnabled": true,
            "pushNotificationsEnabled": true,
            "emailNotificationsEnabled": true,
            "notifyOnLikes": true,
            "notifyOnComments": true,
            "notifyOnFollows": true,
            "notifyOnMentions": true,
            "notifyOnPrayerRequests": true,
            "allowMessagesFromEveryone": true,
            "showActivityStatus": true,
            "allowTagging": true,
            "hasCompletedOnboarding": false,
            "authProvider": "apple"
        ]
        
        try await firestore.collection(CollectionPath.users)
            .document(user.uid)
            .setData(userData)
        
        // Sync to Algolia
        try? await AlgoliaSyncService.shared.syncUser(userId: user.uid, userData: userData)
    }
    
    // MARK: - Firestore Operations
    
    /// Reference to a collection
    func collection(_ path: String) -> CollectionReference {
        firestore.collection(path)
    }
    
    /// Reference to a document
    func document(_ path: String) -> DocumentReference {
        firestore.document(path)
    }
    
    /// Save document to Firestore
    func saveDocument<T: Encodable>(_ data: T, to path: String) async throws {
        let encoded = try Firestore.Encoder().encode(data)
        try await firestore.document(path).setData(encoded)
    }
    
    /// Update document in Firestore
    func updateDocument(_ data: [String: Any], at path: String) async throws {
        try await firestore.document(path).updateData(data)
    }
    
    /// Delete document from Firestore
    func deleteDocument(at path: String) async throws {
        try await firestore.document(path).delete()
    }
    
    /// Fetch document from Firestore
    func fetchDocument<T: Decodable>(from path: String, as type: T.Type) async throws -> T {
        let snapshot = try await firestore.document(path).getDocument()
        guard snapshot.exists else {
            throw FirebaseError.documentNotFound
        }
        return try snapshot.data(as: T.self)
    }
    
    /// Fetch collection from Firestore
    func fetchCollection<T: Decodable>(from path: String, as type: T.Type) async throws -> [T] {
        let snapshot = try await firestore.collection(path).getDocuments()
        return try snapshot.documents.compactMap { try $0.data(as: T.self) }
    }
    
    // MARK: - Storage Operations
    
    /// Upload image to Firebase Storage
    func uploadImage(_ image: UIImage, to path: String, compressionQuality: CGFloat = 0.8) async throws -> URL {
        guard let imageData = image.jpegData(compressionQuality: compressionQuality) else {
            throw FirebaseError.imageCompressionFailed
        }
        
        let storageRef = storage.reference().child(path)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        _ = try await storageRef.putDataAsync(imageData, metadata: metadata)
        let downloadURL = try await storageRef.downloadURL()
        return downloadURL
    }
    
    /// Delete file from Firebase Storage
    func deleteFile(at path: String) async throws {
        let storageRef = storage.reference().child(path)
        try await storageRef.delete()
    }
    
    /// Download URL for file in Storage
    func getDownloadURL(for path: String) async throws -> URL {
        let storageRef = storage.reference().child(path)
        return try await storageRef.downloadURL()
    }
    
    // MARK: - Account Deletion
    
    /// Delete all user data from Firestore
    func deleteUserData(userId: String) async throws {
        print("🗑️ FirebaseManager: Deleting user data for: \(userId)")
        
        // Note: In a production app, you might want to do this via a Cloud Function
        // to ensure all related data is properly cleaned up.
        // For now, we'll delete the main user document
        
        do {
            // Delete user's main document
            try await firestore
                .collection(CollectionPath.users)
                .document(userId)
                .delete()
            
            print("✅ FirebaseManager: User document deleted")
            
            // TODO: In a real app, you'd want to:
            // - Delete user's posts
            // - Delete user's comments
            // - Delete user's messages
            // - Delete user's saved posts
            // - Update follower/following relationships
            // - Delete user's profile images from Storage
            // This is best done via a Cloud Function for data consistency
            
        } catch {
            print("❌ FirebaseManager: Failed to delete user data: \(error)")
            throw error
        }
    }
    
    // MARK: - Helper Methods
    
    /// Create searchable keywords from a display name
    /// This enables array-contains queries for user search in messaging
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
        
        // Remove duplicates and return
        return Array(Set(keywords))
    }
}

// MARK: - Firebase Errors

enum FirebaseError: LocalizedError {
    case documentNotFound
    case imageCompressionFailed
    case invalidData
    case unauthorized
    
    var errorDescription: String? {
        switch self {
        case .documentNotFound:
            return "The requested document was not found."
        case .imageCompressionFailed:
            return "Failed to compress image data."
        case .invalidData:
            return "The data format is invalid."
        case .unauthorized:
            return "You are not authorized to perform this action."
        }
    }
}

// MARK: - FirebaseManager Extensions

extension FirebaseManager {
    /// Fetch user document as dictionary (for checking onboarding status)
    func fetchUserDocument(userId: String) async throws -> [String: Any] {
        let snapshot = try await firestore
            .collection(CollectionPath.users)
            .document(userId)
            .getDocument()
        
        guard snapshot.exists, let data = snapshot.data() else {
            throw FirebaseError.documentNotFound
        }
        
        return data
    }
}


