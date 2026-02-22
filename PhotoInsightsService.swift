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
    private let apiKey: String
    
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
    
    private init() {
        // Use the Google API key from configuration
        self.apiKey = "AIzaSyBRg7axwpIAxoKjuSuCBSqCtMuxfkqfE-k"
    }
    
    // MARK: - Main Analysis Function
    
    func analyzeProfilePhoto(imageURL: String, userId: String) async throws -> PhotoInsight {
        // Check cache first
        if let cached = try? await getCachedInsight(userId: userId) {
            print("✅ Using cached photo insights for user: \(userId)")
            return cached
        }
        
        print("🔍 Analyzing photo for user: \(userId)")
        
        // Download image data
        guard let url = URL(string: imageURL) else {
            throw PhotoInsightError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let base64Image = data.base64EncodedString()
        
        // Call Google Cloud Vision API
        let labels = try await detectLabels(base64Image: base64Image)
        
        // Generate badges from labels
        let badges = generateBadges(from: labels)
        
        // Create insight
        let insight = PhotoInsight(
            badges: badges,
            dominantColors: nil,
            analyzedAt: Date()
        )
        
        // Cache result
        try await cacheInsight(insight, userId: userId)
        
        print("✅ Generated \(badges.count) badges for user: \(userId)")
        return insight
    }
    
    // MARK: - Google Cloud Vision API
    
    private func detectLabels(base64Image: String) async throws -> [String] {
        let endpoint = "https://vision.googleapis.com/v1/images:annotate?key=\(apiKey)"
        
        guard let url = URL(string: endpoint) else {
            throw PhotoInsightError.invalidURL
        }
        
        let requestBody: [String: Any] = [
            "requests": [
                [
                    "image": [
                        "content": base64Image
                    ],
                    "features": [
                        [
                            "type": "LABEL_DETECTION",
                            "maxResults": 10
                        ]
                    ]
                ]
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PhotoInsightError.networkError
        }
        
        guard httpResponse.statusCode == 200 else {
            print("❌ Vision API error: \(httpResponse.statusCode)")
            if let errorString = String(data: data, encoding: .utf8) {
                print("   Response: \(errorString)")
            }
            throw PhotoInsightError.apiError(httpResponse.statusCode)
        }
        
        // Parse response
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let responses = json?["responses"] as? [[String: Any]],
              let firstResponse = responses.first,
              let labelAnnotations = firstResponse["labelAnnotations"] as? [[String: Any]] else {
            return []
        }
        
        // Extract labels with confidence > 0.7
        let labels = labelAnnotations.compactMap { annotation -> String? in
            guard let description = annotation["description"] as? String,
                  let score = annotation["score"] as? Double,
                  score > 0.7 else {
                return nil
            }
            return description
        }
        
        print("🔍 Detected labels: \(labels.joined(separator: ", "))")
        return labels
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
    
    func batchAnalyzeUsers(userIds: [String]) async {
        print("📸 Starting batch analysis for \(userIds.count) users")
        
        for userId in userIds {
            do {
                // Get user's profile image URL
                let userDoc = try await db.collection("users").document(userId).getDocument()
                guard let imageURL = userDoc.data()?["profileImageURL"] as? String,
                      !imageURL.isEmpty else {
                    continue
                }
                
                // Analyze (will use cache if available)
                _ = try await analyzeProfilePhoto(imageURL: imageURL, userId: userId)
                
                // Rate limit: 1 request per second (free tier safe)
                try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch {
                print("⚠️ Failed to analyze user \(userId): \(error)")
            }
        }
        
        print("✅ Batch analysis complete")
    }
}

// MARK: - Errors

enum PhotoInsightError: Error {
    case invalidURL
    case networkError
    case apiError(Int)
    case parsingError
}
