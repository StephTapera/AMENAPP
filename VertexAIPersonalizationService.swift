//
//  VertexAIPersonalizationService.swift
//  AMENAPP
//
//  ML-powered feed personalization using Google Vertex AI Recommendations
//  Trains on user engagement data to predict post relevance
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseRemoteConfig

// MARK: - Personalization Models

/// User engagement event for ML training
struct EngagementEvent: Codable {
    let userId: String
    let postId: String
    let eventType: EventType
    let timestamp: Date
    let duration: TimeInterval? // For view events
    let metadata: [String: String]?
    
    enum EventType: String, Codable {
        case view = "view"
        case reaction = "reaction"
        case comment = "comment"
        case share = "share"
        case save = "save"
        case skip = "skip"
        case report = "report"
    }
}

/// Personalized feed prediction from Vertex AI
struct FeedPrediction: Codable {
    let postId: String
    let relevanceScore: Double // 0.0 - 1.0
    let confidenceScore: Double
    let features: PredictionFeatures
    
    struct PredictionFeatures: Codable {
        let topicMatch: Double
        let authorAffinity: Double
        let engagementQuality: Double
        let recency: Double
        let diversityBonus: Double
    }
}

/// Notification relevance prediction
struct NotificationPrediction: Codable {
    let notificationId: String
    let userId: String
    let relevanceScore: Double // 0.0 - 1.0
    let predictedEngagement: Double // Probability user will tap
    let recommendedAction: RecommendedAction
    
    enum RecommendedAction: String, Codable {
        case send = "send"
        case delay = "delay"
        case batch = "batch"
        case suppress = "suppress"
    }
}

// MARK: - Vertex AI Personalization Service

/// ML-powered personalization using Vertex AI
class VertexAIPersonalizationService {
    static let shared = VertexAIPersonalizationService()
    private let db = Firestore.firestore()
    
    // Vertex AI Configuration from Firebase Remote Config
    private var vertexAIProjectId: String {
        RemoteConfig.remoteConfig().configValue(forKey: "vertex_ai_project_id").stringValue ?? ""
    }
    private let vertexAIRegion = "us-central1"
    private let modelEndpoint = "" // TODO: Deploy model and add endpoint
    
    private init() {}
    
    // MARK: - Engagement Tracking
    
    /// Record user engagement event for ML training
    func recordEngagement(_ event: EngagementEvent) async throws {
        print("📊 [ENGAGEMENT] Recording: \(event.eventType.rawValue) on post \(event.postId)")
        
        // Store in Firestore for batch training
        let eventData: [String: Any] = [
            "userId": event.userId,
            "postId": event.postId,
            "eventType": event.eventType.rawValue,
            "timestamp": FieldValue.serverTimestamp(),
            "duration": event.duration ?? 0,
            "metadata": event.metadata ?? [:]
        ]
        
        try await db.collection("engagementEvents")
            .addDocument(data: eventData)
        
        // Also update real-time user interests (for hybrid approach)
        await updateUserInterests(event)
    }
    
    /// Update user interests based on engagement
    private func updateUserInterests(_ event: EngagementEvent) async {
        // Weight different event types
        let weights: [EngagementEvent.EventType: Double] = [
            .view: 1.0,
            .reaction: 5.0,
            .comment: 10.0,
            .share: 15.0,
            .save: 12.0,
            .skip: -2.0,
            .report: -10.0
        ]
        
        guard let weight = weights[event.eventType] else { return }
        
        // Update in HomeFeedAlgorithm
        if weight > 0 {
            let interactionType: HomeFeedAlgorithm.InteractionType = {
                switch event.eventType {
                case .view: return .view
                case .reaction: return .reaction
                case .comment: return .comment
                case .share: return .share
                default: return .view
                }
            }()
            
            // Note: This requires fetching the post to update interests
            // In production, store post metadata with event for efficiency
        }
    }
    
    // MARK: - Engagement Data Export
    
    /// Export engagement data for Vertex AI training
    func exportEngagementData(startDate: Date, endDate: Date) async throws -> URL {
        print("📤 [EXPORT] Exporting engagement data from \(startDate) to \(endDate)")
        
        let snapshot = try await db.collection("engagementEvents")
            .whereField("timestamp", isGreaterThanOrEqualTo: startDate)
            .whereField("timestamp", isLessThanOrEqualTo: endDate)
            .getDocuments()
        
        // Convert to Vertex AI format (JSONL)
        var jsonlLines: [String] = []
        
        for doc in snapshot.documents {
            let data = doc.data()
            if let jsonData = try? JSONSerialization.data(withJSONObject: data),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                jsonlLines.append(jsonString)
            }
        }
        
        // Write to temporary file
        let fileName = "engagement_export_\(Date().timeIntervalSince1970).jsonl"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        try jsonlLines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
        
        print("✅ [EXPORT] Exported \(jsonlLines.count) events to \(fileURL.path)")
        
        return fileURL
    }
    
    /// Export to Google Cloud Storage for Vertex AI training
    func exportToGCS(bucket: String, startDate: Date, endDate: Date) async throws {
        let localFile = try await exportEngagementData(startDate: startDate, endDate: endDate)
        
        // TODO: Upload to GCS using Firebase Storage or Google Cloud SDK
        print("📤 [GCS] Upload to gs://\(bucket)/training-data/\(localFile.lastPathComponent)")
        
        // For now, just log the instruction
        print("""
        📋 [INSTRUCTION] To upload to GCS, run:
        gsutil cp \(localFile.path) gs://\(bucket)/training-data/
        """)
    }
    
    // MARK: - Personalized Feed Prediction
    
    /// Get personalized feed ranking from Vertex AI
    func getPredictedFeed(for userId: String, candidatePosts: [String]) async throws -> [FeedPrediction] {
        guard !vertexAIProjectId.isEmpty, !modelEndpoint.isEmpty else {
            throw NSError(
                domain: "VertexAI",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Vertex AI not configured"]
            )
        }
        
        print("🤖 [VERTEX AI] Requesting predictions for \(candidatePosts.count) posts...")
        
        // Call Vertex AI Prediction API
        let url = URL(string: "https://\(vertexAIRegion)-aiplatform.googleapis.com/v1/projects/\(vertexAIProjectId)/locations/\(vertexAIRegion)/endpoints/\(modelEndpoint):predict")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // TODO: Add OAuth2 token for authentication
        
        let body: [String: Any] = [
            "instances": candidatePosts.map { postId in
                [
                    "userId": userId,
                    "postId": postId
                ]
            }
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NSError(domain: "VertexAI", code: 500, userInfo: [NSLocalizedDescriptionKey: "Prediction API error"])
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let predictions = json?["predictions"] as? [[String: Any]] else {
            throw NSError(domain: "VertexAI", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid prediction response"])
        }
        
        // Parse predictions
        var results: [FeedPrediction] = []
        for (index, prediction) in predictions.enumerated() {
            guard let relevanceScore = prediction["relevanceScore"] as? Double else { continue }
            
            results.append(FeedPrediction(
                postId: candidatePosts[index],
                relevanceScore: relevanceScore,
                confidenceScore: prediction["confidence"] as? Double ?? 0.5,
                features: FeedPrediction.PredictionFeatures(
                    topicMatch: prediction["topicMatch"] as? Double ?? 0.0,
                    authorAffinity: prediction["authorAffinity"] as? Double ?? 0.0,
                    engagementQuality: prediction["engagementQuality"] as? Double ?? 0.0,
                    recency: prediction["recency"] as? Double ?? 0.0,
                    diversityBonus: prediction["diversityBonus"] as? Double ?? 0.0
                )
            ))
        }
        
        print("✅ [VERTEX AI] Received \(results.count) predictions")
        
        return results
    }
    
    /// Hybrid ranking: Combine Vertex AI predictions with local algorithm
    func getHybridFeed(for userId: String, candidatePosts: [Post]) async throws -> [Post] {
        // Step 1: Get Vertex AI predictions
        let postIds = candidatePosts.map { $0.id.uuidString }
        let predictions: [FeedPrediction]
        
        do {
            predictions = try await getPredictedFeed(for: userId, candidatePosts: postIds)
        } catch {
            print("⚠️ [HYBRID] Vertex AI failed, falling back to local algorithm")
            // Fallback to local algorithm
            return HomeFeedAlgorithm.shared.rankPosts(
                candidatePosts,
                for: HomeFeedAlgorithm.shared.userInterests
            )
        }
        
        // Step 2: Combine with local scores (70% Vertex AI, 30% local)
        let localScores = candidatePosts.map { post in
            HomeFeedAlgorithm.shared.scorePost(post, for: HomeFeedAlgorithm.shared.userInterests)
        }
        
        var scoredPosts: [(post: Post, score: Double)] = []
        
        for (index, post) in candidatePosts.enumerated() {
            let vertexScore = predictions.first(where: { $0.postId == post.id.uuidString })?.relevanceScore ?? 0.5
            let localScore = localScores[index]
            
            // Weighted combination
            let combinedScore = (vertexScore * 100 * 0.7) + (localScore * 0.3)
            
            scoredPosts.append((post: post, score: combinedScore))
        }
        
        // Sort by combined score
        return scoredPosts
            .sorted { $0.score > $1.score }
            .map { $0.post }
    }
    
    // MARK: - Smart Notifications
    
    /// Predict notification relevance
    func predictNotificationRelevance(
        userId: String,
        notificationType: String,
        metadata: [String: Any]
    ) async throws -> NotificationPrediction {
        
        print("🔔 [NOTIFICATION] Predicting relevance for user \(userId)")
        
        // Get user's notification engagement history
        let history = try await db.collection("notificationEngagement")
            .whereField("userId", isEqualTo: userId)
            .limit(to: 100)
            .getDocuments()
        
        // Calculate engagement rate
        let totalSent = history.documents.count
        let totalOpened = history.documents.filter { ($0.data()["opened"] as? Bool) == true }.count
        let baseEngagementRate = totalSent > 0 ? Double(totalOpened) / Double(totalSent) : 0.5
        
        // Adjust based on notification type
        let typeMultipliers: [String: Double] = [
            "comment": 1.2,
            "reaction": 0.9,
            "follow": 1.1,
            "message": 1.3,
            "mention": 1.4
        ]
        let typeMultiplier = typeMultipliers[notificationType] ?? 1.0
        
        // Time-based adjustment (avoid night notifications)
        let hour = Calendar.current.component(.hour, from: Date())
        let timeMultiplier: Double
        if hour >= 22 || hour < 8 {
            timeMultiplier = 0.3 // Nighttime - low priority
        } else if hour >= 9 && hour <= 20 {
            timeMultiplier = 1.0 // Daytime - normal priority
        } else {
            timeMultiplier = 0.7 // Early morning/late evening
        }
        
        // Calculate final score
        let relevanceScore = baseEngagementRate * typeMultiplier * timeMultiplier
        let predictedEngagement = min(1.0, max(0.0, relevanceScore))
        
        // Determine action
        let recommendedAction: NotificationPrediction.RecommendedAction
        if predictedEngagement >= 0.7 {
            recommendedAction = .send
        } else if predictedEngagement >= 0.4 {
            recommendedAction = .batch
        } else if hour >= 22 || hour < 8 {
            recommendedAction = .delay
        } else {
            recommendedAction = .suppress
        }
        
        print("🔔 [RESULT] Score: \(predictedEngagement), Action: \(recommendedAction.rawValue)")
        
        return NotificationPrediction(
            notificationId: UUID().uuidString,
            userId: userId,
            relevanceScore: relevanceScore,
            predictedEngagement: predictedEngagement,
            recommendedAction: recommendedAction
        )
    }
    
    /// Filter notifications before sending
    func filterNotifications(_ notifications: [AIFilteredNotification]) async throws -> [AIFilteredNotification] {
        print("🔔 [FILTER] Processing \(notifications.count) notifications...")
        
        var filtered: [AIFilteredNotification] = []
        
        for notification in notifications {
            let prediction = try await predictNotificationRelevance(
                userId: notification.userId,
                notificationType: notification.type,
                metadata: notification.metadata
            )
            
            // Only send high-relevance notifications
            if prediction.recommendedAction == .send {
                filtered.append(notification)
            } else {
                print("🔕 [SUPPRESSED] \(notification.type) for user \(notification.userId) (score: \(prediction.relevanceScore))")
            }
        }
        
        print("✅ [FILTER] Sending \(filtered.count)/\(notifications.count) notifications")
        
        return filtered
    }
    
    /// Track notification engagement for model improvement
    func recordNotificationEngagement(
        notificationId: String,
        userId: String,
        opened: Bool,
        timeToOpen: TimeInterval?
    ) async throws {
        
        let engagementData: [String: Any] = [
            "notificationId": notificationId,
            "userId": userId,
            "opened": opened,
            "timeToOpen": timeToOpen ?? 0,
            "timestamp": FieldValue.serverTimestamp()
        ]
        
        try await db.collection("notificationEngagement")
            .addDocument(data: engagementData)
        
        print("📊 [ENGAGEMENT] Recorded notification engagement: opened=\(opened)")
    }
    
    // MARK: - Model Training (Cloud Function Integration)
    
    /// Trigger Vertex AI model training with latest data
    func triggerModelTraining() async throws {
        print("🎓 [TRAINING] Triggering Vertex AI model training...")
        
        // Export latest engagement data
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -30, to: endDate)!
        
        let exportFile = try await exportEngagementData(startDate: startDate, endDate: endDate)
        
        print("""
        ✅ [TRAINING] Data exported. Next steps:
        1. Upload to GCS: gsutil cp \(exportFile.path) gs://YOUR_BUCKET/training-data/
        2. Trigger training job in Vertex AI console
        3. Deploy new model version
        4. Update modelEndpoint in code
        """)
    }
}

// MARK: - Supporting Types

struct AIFilteredNotification {
    let userId: String
    let type: String
    let metadata: [String: Any]
}
