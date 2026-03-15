//
//  FirebaseManager.swift
//  AMENAPP
//
//  Created by Steph on 1/19/26.
//

import Foundation
import UIKit
import ImageIO
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
        
        // ✅ Firestore settings are configured in AppDelegate.swift
        // (must be set ONCE, immediately after FirebaseApp.configure())
        print("✅ FirebaseManager initialized")
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
    func signUp(email: String, password: String, displayName: String, username: String? = nil, birthYear: Int? = nil) async throws -> FirebaseAuth.User {
        print("🔐 FirebaseManager: Creating new user account...")
        
        // Create Firebase Auth user
        let result = try await auth.createUser(withEmail: email, password: password)
        let user = result.user
        
        dlog("✅ FirebaseManager: Auth user created")
        
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
        let now = Timestamp(date: Date())
        let userData: [String: Any] = [
            "uid": user.uid, // ✅ CRITICAL: Required by security rules
            "email": email,
            "displayName": displayName,
            "displayNameLowercase": displayName.lowercased(),
            "username": finalUsername,
            "usernameLowercase": finalUsername,
            "initials": initials,
            "bio": "",
            "profileImageURL": NSNull(),
            "nameKeywords": nameKeywords, // For search functionality
            "createdAt": now,
            "updatedAt": now,
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
            // ✅ P0-3: Record ToS + Privacy Policy acceptance at account creation.
            // These are stamped here as a baseline; the onboarding flow re-stamps
            // them with tosAcceptedAt once the user explicitly taps "I Agree".
            // Version strings MUST be bumped here whenever ToS/PP changes.
            "tosVersion": "1.0",
            "privacyPolicyVersion": "1.0",
            "tosAcceptedAt": now,
            "privacyPolicyAcceptedAt": now
        ]

        // Merge birthYear if provided — the onUserDocCreated Cloud Function reads this
        // and writes back the server-authoritative ageTier field.
        var finalUserData = userData
        if let year = birthYear {
            finalUserData["birthYear"] = year
        }
        
        do {
            try await firestore.collection(CollectionPath.users)
                .document(user.uid)
                .setData(finalUserData)

            print("✅ FirebaseManager: User profile created successfully!")

            // ── Username lookup index — public read, enables username availability checks ──
            // SECURITY FIX: Store only uid (not email) to prevent unauthenticated email enumeration.
            // Username-based sign-in must be handled server-side via a Cloud Function.
            do {
                try await firestore.collection("usernameLookup")
                    .document(finalUsername)
                    .setData(["uid": user.uid])
                print("✅ FirebaseManager: Username lookup index written")
            } catch {
                print("⚠️ FirebaseManager: Username lookup index write failed (non-critical): \(error)")
            }

            // ⭐️ Sync to Algolia for instant search
            do {
                try await AlgoliaSyncService.shared.syncUser(userId: user.uid, userData: finalUserData)
                print("✅ FirebaseManager: User synced to Algolia")
            } catch {
                print("⚠️ FirebaseManager: Algolia sync failed (non-critical): \(error)")
                // Don't throw - user creation succeeded, search sync is optional
            }
            
            // 🔒 TRUST-BY-DESIGN: Create default privacy settings
            do {
                let defaultSettings = TrustPrivacySettings.conservative(userId: user.uid)
                let privacyData = try Firestore.Encoder().encode(defaultSettings)
                try await firestore.collection("user_privacy_settings")
                    .document(user.uid)
                    .setData(privacyData)
                print("✅ FirebaseManager: Privacy settings initialized with conservative defaults")
            } catch {
                print("⚠️ FirebaseManager: Privacy settings creation failed (non-critical): \(error)")
                // Don't throw - user creation succeeded, privacy settings can be created later
            }
            
            print("🎉 Complete user setup finished for: \(displayName)")

            // ✉️ Send email verification
            do {
                try await user.sendEmailVerification()
                #if DEBUG
                print("✅ FirebaseManager: Verification email sent to \(email)")
                #endif
            } catch {
                print("⚠️ FirebaseManager: Failed to send verification email (non-critical): \(error)")
                // Don't throw - user creation succeeded, they can verify later
            }

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
        #if DEBUG
        print("✅ FirebaseManager: Password reset email sent to \(email)")
        #endif
    }

    // MARK: - Email Verification

    /// Send email verification to current user
    func sendEmailVerification() async throws {
        guard let user = auth.currentUser else {
            throw FirebaseError.unauthorized
        }

        guard !user.isEmailVerified else {
            print("ℹ️ FirebaseManager: Email already verified")
            return
        }

        try await user.sendEmailVerification()
        #if DEBUG
        print("✅ FirebaseManager: Verification email sent to \(user.email ?? "unknown")")
        #endif
    }

    /// Reload current user to check email verification status
    func reloadUser() async throws {
        guard let user = auth.currentUser else {
            throw FirebaseError.unauthorized
        }

        try await user.reload()
        #if DEBUG
        print("✅ FirebaseManager: User reloaded, emailVerified=\(user.isEmailVerified)")
        #endif
    }

    /// Check if current user's email is verified
    var isEmailVerified: Bool {
        auth.currentUser?.isEmailVerified ?? false
    }

    // MARK: - Passwordless Email Link Sign-In

    /// Send sign-in link to email (passwordless authentication)
    func sendSignInLink(toEmail email: String) async throws {
        let actionCodeSettings = ActionCodeSettings()
        actionCodeSettings.url = URL(string: "https://amen.page.link/emailSignIn")! // Replace with your deep link
        actionCodeSettings.handleCodeInApp = true
        actionCodeSettings.setIOSBundleID(Bundle.main.bundleIdentifier ?? "com.amenapp")

        try await auth.sendSignInLink(toEmail: email, actionCodeSettings: actionCodeSettings)
        #if DEBUG
        print("✅ FirebaseManager: Sign-in link sent to \(email)")
        #endif

        // P0-4 FIX: Save email in Keychain (not UserDefaults) — it's PII
        SecureStorage.save(email, account: "emailForSignIn")
    }

    /// Sign in with email link (called when user clicks the link)
    func signInWithEmailLink(email: String, link: String) async throws -> FirebaseAuth.User {
        guard auth.isSignIn(withEmailLink: link) else {
            throw NSError(domain: "AuthError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid sign-in link"])
        }

        let result = try await auth.signIn(withEmail: email, link: link)
        #if DEBUG
        print("✅ FirebaseManager: Signed in with email link for \(email)")
        #endif

        // P0-4 FIX: Clear email from Keychain after use
        SecureStorage.delete(account: "emailForSignIn")

        // Check if this is a new user and create profile if needed
        if result.additionalUserInfo?.isNewUser == true {
            // Extract name from email for now (can be updated later)
            let displayName = email.components(separatedBy: "@").first?.capitalized ?? "User"
            let username = email.components(separatedBy: "@").first?.lowercased() ?? "user"

            // Create minimal profile (user can complete onboarding later)
            let userData: [String: Any] = [
                "uid": result.user.uid,
                "email": email,
                "displayName": displayName,
                "displayNameLowercase": displayName.lowercased(),
                "username": username,
                "usernameLowercase": username,
                "initials": String(displayName.prefix(1)).uppercased(),
                "bio": "",
                "profileImageURL": NSNull(),
                "nameKeywords": createNameKeywords(from: displayName),
                "createdAt": Timestamp(date: Date()),
                "updatedAt": Timestamp(date: Date()),
                "followersCount": 0,
                "followingCount": 0,
                "postsCount": 0,
                "isPrivate": false,
                "hasCompletedOnboarding": false
            ]

            try await firestore.collection(CollectionPath.users)
                .document(result.user.uid)
                .setData(userData)

            print("✅ FirebaseManager: Email link user profile created")
        }

        return result.user
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
            "uid": user.uid, // ✅ CRITICAL: Required by security rules
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
            "authProvider": "google",
            // ToS + Privacy Policy acceptance stamped at account creation.
            // Google/Apple IdP accounts implicitly accept by completing sign-in.
            "tosVersion": "1.0",
            "privacyPolicyVersion": "1.0",
            "tosAcceptedAt": Timestamp(date: Date()),
            "privacyPolicyAcceptedAt": Timestamp(date: Date())
        ]
        
        try await firestore.collection(CollectionPath.users)
            .document(user.uid)
            .setData(userData)
        
        // Username lookup index — uid only (no email to prevent enumeration)
        do {
            try await firestore.collection("usernameLookup")
                .document(username)
                .setData(["uid": user.uid])
            print("✅ FirebaseManager: Username lookup index written (Google)")
        } catch {
            print("⚠️ FirebaseManager: Username lookup index write failed (non-critical): \(error)")
        }
        
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
            "uid": user.uid, // ✅ CRITICAL: Required by security rules
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
            "authProvider": "apple",
            // ToS + Privacy Policy acceptance stamped at account creation.
            "tosVersion": "1.0",
            "privacyPolicyVersion": "1.0",
            "tosAcceptedAt": Timestamp(date: Date()),
            "privacyPolicyAcceptedAt": Timestamp(date: Date())
        ]
        
        try await firestore.collection(CollectionPath.users)
            .document(user.uid)
            .setData(userData)
        
        // Username lookup index — uid only (no email to prevent enumeration)
        do {
            try await firestore.collection("usernameLookup")
                .document(username)
                .setData(["uid": user.uid])
            print("✅ FirebaseManager: Username lookup index written (Apple)")
        } catch {
            print("⚠️ FirebaseManager: Username lookup index write failed (non-critical): \(error)")
        }
        
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
    
    /// Update document in Firestore (creates if doesn't exist)
    func updateDocument(_ data: [String: Any], at path: String) async throws {
        try await firestore.document(path).setData(data, merge: true)
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
    /// P0 FIX: Strips EXIF metadata (including GPS location) before upload.
    /// `UIImage.jpegData` preserves EXIF from the source CGImage; we must re-encode
    /// through CGImageDestination with kCGImageDestinationEmbedThumbnail=false and
    /// no properties dict to produce a clean, EXIF-free JPEG.
    func uploadImage(_ image: UIImage, to path: String, compressionQuality: CGFloat = 0.8) async throws -> URL {
        guard let imageData = Self.jpegDataStrippingEXIF(image, compressionQuality: compressionQuality) else {
            throw FirebaseError.imageCompressionFailed
        }

        // Enforce a 10 MB upload limit to prevent runaway uploads.
        let maxBytes = 10 * 1024 * 1024
        guard imageData.count <= maxBytes else {
            throw NSError(
                domain: "FirebaseManager",
                code: 413,
                userInfo: [NSLocalizedDescriptionKey: "Image exceeds 10 MB limit after compression."]
            )
        }

        let storageRef = storage.reference().child(path)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        _ = try await storageRef.putDataAsync(imageData, metadata: metadata)
        let downloadURL = try await storageRef.downloadURL()
        return downloadURL
    }

    /// Produce JPEG data with all EXIF/GPS metadata stripped.
    /// Uses ImageIO to re-encode without any source properties.
    private static func jpegDataStrippingEXIF(_ image: UIImage, compressionQuality: CGFloat) -> Data? {
        guard let cgImage = image.cgImage else {
            // Fallback for CIImage-backed UIImages
            return image.jpegData(compressionQuality: compressionQuality)
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            "public.jpeg" as CFString,
            1,
            nil
        ) else { return nil }

        // Pass nil for properties — this omits all EXIF, GPS, IPTC, TIFF metadata.
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: compressionQuality
        ]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }

        return data as Data
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
    /// GDPR/CCPA: Triggers a Cloud Function for full cascade deletion of posts,
    /// comments, messages, notifications, follower relationships, and Storage files.
    /// The Cloud Function runs with admin SDK and handles all sub-collections atomically.
    func deleteUserData(userId: String) async throws {
        print("🗑️ FirebaseManager: Queuing cascade deletion for: \(userId)")

        do {
            // 1. Write a deletion request document — the Cloud Function watches this
            //    collection and cascades deletion of all associated data atomically.
            //    (Deploy the deleteUser Cloud Function to process these requests.)
            try await firestore
                .collection("deletionRequests")
                .document(userId)
                .setData([
                    "userId": userId,
                    "requestedAt": FieldValue.serverTimestamp(),
                    "status": "pending"
                ])

            print("✅ FirebaseManager: Cascade deletion request queued (Cloud Function will handle posts/comments/messages/storage)")

            // 2. Delete the main user auth profile immediately so the user
            //    cannot log back in while the cascade is in progress.
            // Note: Auth.auth().currentUser?.delete() is called by the caller (AccountSettingsView)
            //       after this function returns, so we don't double-delete here.

        } catch {
            print("❌ FirebaseManager: Failed to queue deletion request: \(error)")
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
        if words.count >= 2, let firstName = words.first, let lastName = words.last {
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
    case rateLimitExceeded
    
    var errorDescription: String? {
        switch self {
        case .documentNotFound:
            return "The requested document was not found."
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please try again later."
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
    
    // MARK: - Account Linking
    
    /// Get list of currently linked auth providers
    func getLinkedProviders() -> [String] {
        guard let user = auth.currentUser else { return [] }
        return user.providerData.map { $0.providerID }
    }
    
    /// Check if a specific provider is already linked
    func isProviderLinked(_ provider: String) -> Bool {
        return getLinkedProviders().contains(provider)
    }
    
    /// Link Google account to existing account
    @MainActor
    func linkGoogleAccount() async throws {
        guard let user = auth.currentUser else {
            throw NSError(domain: "AuthError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user is currently signed in"])
        }
        
        // Check if Google is already linked
        if isProviderLinked("google.com") {
            throw NSError(domain: "AuthError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Google account is already linked"])
        }
        
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
        let googleUser = result.user
        
        guard let idToken = googleUser.idToken?.tokenString else {
            throw FirebaseError.invalidData
        }
        
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: googleUser.accessToken.tokenString
        )
        
        try await user.link(with: credential)
        print("✅ FirebaseManager: Google account linked successfully")
    }
    
    /// Link Apple account to existing account
    @MainActor
    func linkAppleAccount(idToken: String, nonce: String, fullName: PersonNameComponents?) async throws {
        guard let user = auth.currentUser else {
            throw NSError(domain: "AuthError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user is currently signed in"])
        }
        
        // Check if Apple is already linked
        if isProviderLinked("apple.com") {
            throw NSError(domain: "AuthError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Apple account is already linked"])
        }
        
        let credential = OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: nonce,
            fullName: fullName
        )
        
        try await user.link(with: credential)
        print("✅ FirebaseManager: Apple account linked successfully")
        
        // Update display name if provided and not already set
        if let fullName = fullName,
           let givenName = fullName.givenName,
           user.displayName == nil || user.displayName?.isEmpty == true {
            let displayName = [givenName, fullName.familyName].compactMap { $0 }.joined(separator: " ")
            
            let changeRequest = user.createProfileChangeRequest()
            changeRequest.displayName = displayName
            try await changeRequest.commitChanges()
            
            // Update Firestore
            try await firestore.collection(CollectionPath.users)
                .document(user.uid)
                .updateData(["displayName": displayName])
        }
    }
    
    /// Unlink auth provider from account
    func unlinkProvider(_ providerID: String) async throws {
        guard let user = auth.currentUser else {
            throw NSError(domain: "AuthError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user is currently signed in"])
        }
        
        // Prevent unlinking if it's the only provider
        if user.providerData.count <= 1 {
            throw NSError(domain: "AuthError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot unlink your only sign-in method. Please add another method first."])
        }
        
        _ = try await user.unlink(fromProvider: providerID)
        print("✅ FirebaseManager: Provider \(providerID) unlinked successfully")
    }
}


