//
//  SocialLinksService.swift
//  AMENAPP
//
//  Created by Steph on 1/21/26.
//
//  Service for managing user social media links
//

import Foundation
import FirebaseFirestore
import Combine
import FirebaseAuth

// MARK: - Social Link Model

struct SocialLinkData: Codable, Identifiable, Equatable {
    var id = UUID()
    var platform: String
    var username: String
    var url: String
    
    enum CodingKeys: String, CodingKey {
        case platform
        case username
        case url
    }
    
    init(platform: String, username: String) {
        self.platform = platform
        self.username = username
        self.url = SocialLinkData.generateURL(platform: platform, username: username)
    }
    
    static func generateURL(platform: String, username: String) -> String {
        let cleanUsername = username.replacingOccurrences(of: "@", with: "")
        
        switch platform.lowercased() {
        case "instagram":
            return "https://instagram.com/\(cleanUsername)"
        case "twitter", "x":
            return "https://twitter.com/\(cleanUsername)"
        case "youtube":
            return "https://youtube.com/@\(cleanUsername)"
        case "tiktok":
            return "https://tiktok.com/@\(cleanUsername)"
        case "linkedin":
            return "https://linkedin.com/in/\(cleanUsername)"
        case "facebook":
            return "https://facebook.com/\(cleanUsername)"
        default:
            return cleanUsername
        }
    }
}

// MARK: - Social Links Service

@MainActor
class SocialLinksService: ObservableObject {
    static let shared = SocialLinksService()
    
    @Published var socialLinks: [SocialLinkData] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let db = Firestore.firestore()
    private let firebaseManager = FirebaseManager.shared
    
    private init() {}
    
    // MARK: - Update Social Links
    
    /// Save or update user's social links
    func updateSocialLinks(_ links: [SocialLinkData]) async throws {
        print("💾 Updating social links...")
        
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        // Convert to Firestore format
        let linksData = links.map { link -> [String: Any] in
            return [
                "platform": link.platform,
                "username": link.username,
                "url": link.url
            ]
        }
        
        try await db.collection(FirebaseManager.CollectionPath.users)
            .document(userId)
            .updateData([
                "socialLinks": linksData,
                "updatedAt": Date()
            ])
        
        print("✅ Social links updated successfully")
        
        // Update local state
        socialLinks = links
        
        // Haptic feedback
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }
    
    // MARK: - Add Social Link
    
    /// Add a new social link
    func addSocialLink(platform: String, username: String) async throws {
        print("➕ Adding social link: \(platform)")
        
        // Create new link
        let newLink = SocialLinkData(platform: platform, username: username)
        
        // Add to array
        var updatedLinks = socialLinks
        
        // Remove existing link for same platform
        updatedLinks.removeAll { $0.platform.lowercased() == platform.lowercased() }
        
        // Add new link
        updatedLinks.append(newLink)
        
        // Update Firestore
        try await updateSocialLinks(updatedLinks)
        
        print("✅ Social link added")
    }
    
    // MARK: - Remove Social Link
    
    /// Remove a social link
    func removeSocialLink(platform: String) async throws {
        print("➖ Removing social link: \(platform)")
        
        // Remove from array
        var updatedLinks = socialLinks
        updatedLinks.removeAll { $0.platform.lowercased() == platform.lowercased() }
        
        // Update Firestore
        try await updateSocialLinks(updatedLinks)
        
        print("✅ Social link removed")
    }
    
    // MARK: - Fetch Social Links
    
    /// Fetch user's social links from Firestore
    func fetchSocialLinks(userId: String? = nil) async throws -> [SocialLinkData] {
        print("📥 Fetching social links...")
        
        let targetUserId = userId ?? firebaseManager.currentUser?.uid
        
        guard let targetUserId = targetUserId else {
            throw FirebaseError.unauthorized
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let userDoc = try await db.collection(FirebaseManager.CollectionPath.users)
            .document(targetUserId)
            .getDocument()
        
        guard let linksData = userDoc.data()?["socialLinks"] as? [[String: Any]] else {
            print("⚠️ No social links found")
            return []
        }
        
        let links = linksData.compactMap { linkDict -> SocialLinkData? in
            guard let platform = linkDict["platform"] as? String,
                  let username = linkDict["username"] as? String else {
                return nil
            }
            
            return SocialLinkData(platform: platform, username: username)
        }
        
        print("✅ Fetched \(links.count) social links")
        
        // Update local state if fetching for current user
        if userId == nil {
            socialLinks = links
        }
        
        return links
    }
    
    // MARK: - Validation
    
    /// Validate username format for platform
    func validateUsername(platform: String, username: String) -> (isValid: Bool, error: String?) {
        let cleanUsername = username.replacingOccurrences(of: "@", with: "")
        
        // Check for empty
        guard !cleanUsername.isEmpty else {
            return (false, "Username cannot be empty")
        }
        
        // Platform-specific validation
        switch platform.lowercased() {
        case "instagram", "twitter", "x", "tiktok":
            // Alphanumeric, underscores, dots, max 30 chars
            let regex = "^[a-zA-Z0-9._]{1,30}$"
            if cleanUsername.range(of: regex, options: .regularExpression) == nil {
                return (false, "Invalid username format for \(platform)")
            }
            
        case "youtube":
            // Alphanumeric, hyphens, underscores
            let regex = "^[a-zA-Z0-9_-]{3,30}$"
            if cleanUsername.range(of: regex, options: .regularExpression) == nil {
                return (false, "Invalid YouTube channel name")
            }
            
        case "linkedin":
            // Alphanumeric, hyphens
            let regex = "^[a-zA-Z0-9-]{3,100}$"
            if cleanUsername.range(of: regex, options: .regularExpression) == nil {
                return (false, "Invalid LinkedIn profile name")
            }
            
        default:
            break
        }
        
        return (true, nil)
    }
    
    // MARK: - Helper Methods
    
    /// Get icon name for platform
    static func iconForPlatform(_ platform: String) -> String {
        switch platform.lowercased() {
        case "instagram":
            return "camera.circle.fill"
        case "twitter", "x":
            return "bird.circle.fill"
        case "youtube":
            return "play.circle.fill"
        case "tiktok":
            return "music.note.circle.fill"
        case "linkedin":
            return "briefcase.circle.fill"
        case "facebook":
            return "person.circle.fill"
        default:
            return "link.circle.fill"
        }
    }
    
    /// Get color for platform
    static func colorForPlatform(_ platform: String) -> (red: Double, green: Double, blue: Double) {
        switch platform.lowercased() {
        case "instagram":
            return (0.85, 0.35, 0.55)  // Pink/purple
        case "twitter", "x":
            return (0.2, 0.6, 0.95)    // Blue
        case "youtube":
            return (0.9, 0.2, 0.2)     // Red
        case "tiktok":
            return (0.0, 0.0, 0.0)     // Black
        case "linkedin":
            return (0.0, 0.5, 0.75)    // Blue
        case "facebook":
            return (0.23, 0.35, 0.6)   // Blue
        default:
            return (0.5, 0.5, 0.5)     // Gray
        }
    }
    
    /// Available platforms
    static let availablePlatforms = [
        "Instagram",
        "Twitter",
        "YouTube",
        "TikTok",
        "LinkedIn",
        "Facebook"
    ]
}

// MARK: - Extension to Update UserModel

extension FirebaseManager.CollectionPath {
    // Social links are stored in the users collection
    // Structure: users/{userId}/socialLinks: [{ platform, username, url }]
}
