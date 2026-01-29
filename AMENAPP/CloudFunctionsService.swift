//
//  CloudFunctionsService.swift
//  AMENAPP
//
//  Created by Steph on 1/22/26.
//

import Foundation
import FirebaseFunctions
import Combine

/// Service for calling Firebase Cloud Functions from the app
@MainActor
class CloudFunctionsService: ObservableObject {
    static let shared = CloudFunctionsService()
    
    private let functions = Functions.functions()
    
    private init() {
        // Uncomment to use local emulator for testing
        // functions.useEmulator(withHost: "localhost", port: 5001)
    }
    
    // MARK: - Messaging Functions
    
    /// Create or get existing conversation
    func createConversation(
        participantIds: [String],
        isGroup: Bool,
        groupName: String? = nil
    ) async throws -> String {
        let data: [String: Any] = [
            "participantIds": participantIds,
            "isGroup": isGroup,
            "groupName": groupName as Any
        ]
        
        print("📞 Calling createConversation function...")
        
        let result = try await functions.httpsCallable("createConversation").call(data)
        
        guard let response = result.data as? [String: Any],
              let conversationId = response["conversationId"] as? String else {
            throw CloudFunctionsError.invalidResponse
        }
        
        let existed = response["existed"] as? Bool ?? false
        
        if existed {
            print("✅ Found existing conversation: \(conversationId)")
        } else {
            print("✅ Created new conversation: \(conversationId)")
        }
        
        return conversationId
    }
    
    /// Send a message via Cloud Function
    func sendMessage(
        conversationId: String,
        text: String,
        replyToMessageId: String? = nil
    ) async throws -> String {
        var data: [String: Any] = [
            "conversationId": conversationId,
            "text": text
        ]
        
        if let replyToMessageId = replyToMessageId {
            data["replyToMessageId"] = replyToMessageId
        }
        
        print("📞 Calling sendMessage function...")
        
        let result = try await functions.httpsCallable("sendMessage").call(data)
        
        guard let response = result.data as? [String: Any],
              let messageId = response["messageId"] as? String else {
            throw CloudFunctionsError.invalidResponse
        }
        
        print("✅ Message sent: \(messageId)")
        
        return messageId
    }
    
    /// Mark messages as read
    func markMessagesAsRead(
        conversationId: String,
        messageIds: [String]? = nil
    ) async throws {
        var data: [String: Any] = [
            "conversationId": conversationId
        ]
        
        if let messageIds = messageIds {
            data["messageIds"] = messageIds
        }
        
        print("📞 Calling markMessagesAsRead function...")
        
        let result = try await functions.httpsCallable("markMessagesAsRead").call(data)
        
        guard let response = result.data as? [String: Any],
              let success = response["success"] as? Bool,
              success else {
            throw CloudFunctionsError.operationFailed
        }
        
        print("✅ Messages marked as read")
    }
    
    /// Delete a message
    func deleteMessage(
        conversationId: String,
        messageId: String
    ) async throws {
        let data: [String: Any] = [
            "conversationId": conversationId,
            "messageId": messageId
        ]
        
        print("📞 Calling deleteMessage function...")
        
        let result = try await functions.httpsCallable("deleteMessage").call(data)
        
        guard let response = result.data as? [String: Any],
              let success = response["success"] as? Bool,
              success else {
            throw CloudFunctionsError.operationFailed
        }
        
        print("✅ Message deleted")
    }
    
    // MARK: - Feed Generation
    
    /// Generate personalized feed for user
    /// This is called by Cloud Functions based on who the user follows
    func generateFeed(limit: Int = 20) async throws -> [PostFeedItem] {
        print("📰 Requesting personalized feed from Cloud Functions...")
        
        let callable = functions.httpsCallable("generateFeed")
        let data = ["limit": limit]
        
        do {
            let result = try await callable.call(data)
            
            guard let resultData = result.data as? [String: Any],
                  let postsArray = resultData["posts"] as? [[String: Any]] else {
                throw CloudFunctionsError.invalidResponse
            }
            
            // Parse posts (you'll need to adapt this to your Post model)
            let posts = postsArray.compactMap { postData -> PostFeedItem? in
                guard let id = postData["id"] as? String,
                      let content = postData["content"] as? String,
                      let authorId = postData["authorId"] as? String else {
                    return nil
                }
                
                return PostFeedItem(
                    id: id,
                    content: content,
                    authorId: authorId,
                    amenCount: postData["amenCount"] as? Int ?? 0,
                    commentCount: postData["commentCount"] as? Int ?? 0
                )
            }
            
            print("✅ Received \(posts.count) posts in feed")
            return posts
            
        } catch {
            print("❌ Error generating feed: \(error.localizedDescription)")
            throw CloudFunctionsError.functionCallFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Content Reporting
    
    /// Report inappropriate content
    func reportContent(
        contentType: String,
        contentId: String,
        reason: String,
        details: String = ""
    ) async throws {
        print("🚩 Reporting \(contentType): \(contentId)")
        
        let callable = functions.httpsCallable("reportContent")
        let data: [String: Any] = [
            "contentType": contentType,
            "contentId": contentId,
            "reason": reason,
            "details": details
        ]
        
        do {
            let result = try await callable.call(data)
            
            guard let resultData = result.data as? [String: Any],
                  let success = resultData["success"] as? Bool,
                  success else {
                throw CloudFunctionsError.reportFailed
            }
            
            print("✅ Content reported successfully")
            
        } catch {
            print("❌ Error reporting content: \(error.localizedDescription)")
            throw CloudFunctionsError.functionCallFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Notification Management
    
    /// Request test notification (for debugging)
    func requestTestNotification() async throws {
        print("🧪 Requesting test notification...")
        
        let callable = functions.httpsCallable("sendTestNotification")
        
        do {
            _ = try await callable.call()
            print("✅ Test notification sent")
        } catch {
            print("❌ Error sending test notification: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - Helper Functions
    
    /// Test connection to Cloud Functions
    func testConnection() async throws -> Bool {
        do {
            let result = try await functions.httpsCallable("healthCheck").call()
            
            if let response = result.data as? [String: Any],
               let status = response["status"] as? String,
               status == "healthy" {
                print("✅ Cloud Functions connection successful")
                return true
            } else {
                throw CloudFunctionsError.invalidResponse
            }
        } catch {
            print("❌ Cloud Functions connection failed: \(error.localizedDescription)")
            throw error
        }
    }
}

// MARK: - Models

/// Simple feed item model (adapt to your actual Post model)
struct PostFeedItem: Identifiable, Codable {
    let id: String
    let content: String
    let authorId: String
    let amenCount: Int
    let commentCount: Int
}

// MARK: - Errors

enum CloudFunctionsError: LocalizedError {
    case invalidResponse
    case functionCallFailed(String)
    case reportFailed
    case notAuthenticated
    case operationFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .functionCallFailed(let message):
            return "Function call failed: \(message)"
        case .reportFailed:
            return "Failed to submit report"
        case .notAuthenticated:
            return "You must be signed in to perform this action"
        case .operationFailed:
            return "Cloud Function operation failed"
        }
    }
}

// MARK: - Content Report Types

enum ContentReportReason: String, CaseIterable {
    case spam = "spam"
    case harassment = "harassment"
    case hateSpeech = "hate_speech"
    case violence = "violence"
    case inappropriateContent = "inappropriate_content"
    case falseInformation = "false_information"
    case other = "other"
    
    var displayName: String {
        switch self {
        case .spam: return "Spam"
        case .harassment: return "Harassment"
        case .hateSpeech: return "Hate Speech"
        case .violence: return "Violence"
        case .inappropriateContent: return "Inappropriate Content"
        case .falseInformation: return "False Information"
        case .other: return "Other"
        }
    }
    
    var icon: String {
        switch self {
        case .spam: return "envelope.badge"
        case .harassment: return "hand.raised.fill"
        case .hateSpeech: return "exclamationmark.triangle.fill"
        case .violence: return "exclamationmark.shield.fill"
        case .inappropriateContent: return "eye.slash.fill"
        case .falseInformation: return "questionmark.circle.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
}
