//
//  PhotoInsightsService.swift
//  AMENAPP
//
//  AI-powered profile photo analysis using Google Cloud Vision API
//  Generates smart badges like "Outdoor Enthusiast", "Group-focused", etc.
//

import Foundation
import FirebaseFirestore
import FirebaseStorage

// MARK: - Photo Insight Model

struct PhotoInsight: Codable {
    let badges: [String]
    let dominantColors: [String]?
    let analyzedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case badges
        case dominantColors
        case analyzedAt
    }
}

// MARK: - Photo Insights Service

@MainActor
class PhotoInsightsService {
    static let shared = PhotoInsightsService()
    
    private let db = Firestore.firestore()
    // SECURITY: API key is NOT stored on the client.
    // Vision API calls must be proxied through Firebase Cloud Functions.

    // Badge mappings from Vision API labels
    private let badgeMappings: [String: String] = [
        // Nature & Outdoors
        "Nature": "🏔️ Nature Lover",
        "Mountain": "🏔️ Mountain Enthusiast",
        "Hiking": "🥾 Hiker",
        "Beach": "🏖️ Beach Lover",
        "Forest": "🌲 Forest Explorer",
        "Outdoor": "🌿 Outdoor Enthusiast",
        "Sky": "☁️ Sky Gazer",
        "Water": "💧 Water Lover",
        
        // Social & Groups
        "People": "👥 Social",
        "Group": "👥 Group-focused",
        "Crowd": "🎉 Community-oriented",
        "Team": "🤝 Team Player",
        
        // Urban & City
        "City": "🏙️ Urban Explorer",
        "Building": "🏢 City Dweller",
        "Architecture": "🏛️ Architecture Fan",
        "Street": "🚶 Street Explorer",
        
        // Faith & Spirituality
        "Church": "⛪ Church-going",
        "Prayer": "🙏 Prayer Warrior",
        "Bible": "📖 Scripture Reader",
        "Cross": "✝️ Faith-focused",
        "Worship": "🎵 Worshipper",
        
        // Activities
        "Sports": "⚽ Athletic",
        "Music": "🎵 Music Lover",
        "Art": "🎨 Creative",
        "Book": "📚 Reader",
        "Food": "🍽️ Foodie",
        "Travel": "✈️ Traveler",
        "Photography": "📸 Photographer",
        
        // Personality traits (from photo style)
        "Selfie": "📱 Selfie Style",
        "Portrait": "👤 Portrait Focused",
        "Smile": "😊 Joyful"
    ]
    
    private init() {}

    // MARK: - Main Analysis Function

    /// Analyze a profile photo to generate interest badges.
    /// SECURITY: Direct Vision API calls are disabled on the client.
    /// Photo analysis must be proxied through a Firebase Cloud Function (analyzeProfilePhoto callable).
    func analyzeProfilePhoto(imageURL: String, userId: String, currentUserId: String) async throws -> PhotoInsight {
        // Check cache first (can read anyone's cached insights)
        if let cached = try? await getCachedInsight(userId: userId) {
            return cached
        }
        // SECURITY: Vision API key is NOT stored on the client.
        // Photo label analysis must go through Cloud Functions.
        throw NSError(
            domain: "PhotoInsightsService",
            code: 501,
            userInfo: [NSLocalizedDescriptionKey: "Photo insights analysis must be invoked via Cloud Function proxy"]
        )
    }

    // MARK: - (Disabled) Google Cloud Vision API
    // SECURITY: detectLabels is disabled. Vision API calls must be proxied through Cloud Functions.
    private func detectLabels(base64Image: String) async throws -> [String] {
        throw NSError(
            domain: "PhotoInsightsService",
            code: 501,
            userInfo: [NSLocalizedDescriptionKey: "Vision API calls must be proxied through Cloud Functions"]
        )
    }
    
    // MARK: - Badge Generation
    
    private func generateBadges(from labels: [String]) -> [String] {
        var badges = Set<String>()
        
        for label in labels {
            // Check direct matches
            if let badge = badgeMappings[label] {
                badges.insert(badge)
            }
            
            // Check partial matches (e.g., "Mountain range" matches "Mountain")
            for (key, badge) in badgeMappings {
                if label.lowercased().contains(key.lowercased()) {
                    badges.insert(badge)
                }
            }
        }
        
        // Limit to top 3 most relevant badges
        return Array(badges.prefix(3))
    }
    
    // MARK: - Caching
    
    private func getCachedInsight(userId: String) async throws -> PhotoInsight? {
        let doc = try await db.collection("photoInsights").document(userId).getDocument()
        
        guard doc.exists, let data = doc.data() else {
            return nil
        }
        
        guard let badges = data["badges"] as? [String],
              let timestamp = data["analyzedAt"] as? Timestamp else {
            return nil
        }
        
        return PhotoInsight(
            badges: badges,
            dominantColors: data["dominantColors"] as? [String],
            analyzedAt: timestamp.dateValue()
        )
    }
    
    private func cacheInsight(_ insight: PhotoInsight, userId: String) async throws {
        try await db.collection("photoInsights").document(userId).setData([
            "badges": insight.badges,
            "dominantColors": insight.dominantColors ?? [],
            "analyzedAt": Timestamp(date: insight.analyzedAt)
        ])
    }
    
    // MARK: - Batch Processing
    
    func batchAnalyzeUsers(userIds: [String], currentUserId: String) async {
        dlog("📸 Starting batch analysis for \(userIds.count) users")
        
        for userId in userIds {
            do {
                // Get user's profile image URL
                let userDoc = try await db.collection("users").document(userId).getDocument()
                guard let imageURL = userDoc.data()?["profileImageURL"] as? String,
                      !imageURL.isEmpty else {
                    continue
                }
                
                // Analyze (will use cache if available)
                _ = try await analyzeProfilePhoto(imageURL: imageURL, userId: userId, currentUserId: currentUserId)
                
                // Rate limit: 1 request per second (free tier safe)
                try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch {
                dlog("⚠️ Failed to analyze user \(userId): \(error)")
            }
        }
        
        dlog("✅ Batch analysis complete")
    }
}

// MARK: - Errors

enum PhotoInsightError: Error {
    case apiKeyMissing
    case invalidURL
    case networkError
    case apiError(Int)
    case parsingError
    case unsafeContent
    
    var userMessage: String {
        switch self {
        case .unsafeContent:
            return "This image cannot be used as a profile picture. Please choose a different image that aligns with our community guidelines."
        case .networkError:
            return "Network connection issue. Please try again."
        case .apiError:
            return "Unable to process image. Please try again."
        default:
            return "Something went wrong. Please try again."
        }
    }
}
