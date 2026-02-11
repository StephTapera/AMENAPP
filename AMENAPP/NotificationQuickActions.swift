//
//  NotificationQuickActions.swift
//  AMENAPP
//
//  Quick reply and deep linking for notifications
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import UIKit

// MARK: - Quick Reply Service

@MainActor
class QuickReplyService: ObservableObject {
    static let shared = QuickReplyService()
    
    @Published var isPosting = false
    @Published var error: QuickReplyError?
    
    private let db = Firestore.firestore()
    private let interactionsService = PostInteractionsService.shared
    
    private init() {}
    
    /// Post a quick reply comment to a post
    func postQuickReply(postId: String, text: String, authorUsername: String) async throws {
        guard !text.isEmpty else {
            throw QuickReplyError.emptyText
        }
        
        guard let currentUser = Auth.auth().currentUser else {
            throw QuickReplyError.notAuthenticated
        }
        
        isPosting = true
        error = nil
        
        defer { isPosting = false }
        
        do {
            // Get user's profile info
            let userDoc = try await db.collection("users").document(currentUser.uid).getDocument()
            let userData = userDoc.data() ?? [:]
            
            let authorInitials = extractInitials(from: currentUser.displayName ?? authorUsername)
            let profileImageURL = userData["profileImageURL"] as? String
            
            // Post comment using PostInteractionsService
            let commentId = try await interactionsService.addComment(
                postId: postId,
                content: text,
                authorInitials: authorInitials,
                authorUsername: authorUsername,
                authorProfileImageURL: profileImageURL
            )
            
            print("✅ Quick reply posted: \(commentId)")
            
            // Also increment comment count in Firestore post document
            try await db.collection("posts").document(postId).updateData([
                "commentCount": FieldValue.increment(Int64(1))
            ])
            
        } catch {
            self.error = .postFailed(error)
            throw error
        }
    }
    
    private func extractInitials(from name: String) -> String {
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

enum QuickReplyError: LocalizedError {
    case emptyText
    case notAuthenticated
    case postFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "Please enter a comment"
        case .notAuthenticated:
            return "You must be logged in to comment"
        case .postFailed(let error):
            return "Failed to post comment: \(error.localizedDescription)"
        }
    }
}

// MARK: - Deep Link Handler

@MainActor
class NotificationDeepLinkHandler: ObservableObject {
    static let shared = NotificationDeepLinkHandler()
    
    @Published var activeDeepLink: NotificationDeepLink?
    
    private init() {}
    
    /// Handle notification tap from system notification center
    func handleNotificationTap(userInfo: [AnyHashable: Any]) {
        print("🔗 Handling notification tap with userInfo: \(userInfo)")
        
        // Extract notification type and IDs from push notification payload
        guard let type = userInfo["type"] as? String else {
            print("⚠️ No notification type in userInfo")
            return
        }
        
        switch type {
        case "follow":
            if let actorId = userInfo["actorId"] as? String {
                activeDeepLink = .profile(userId: actorId)
            }
            
        case "amen", "comment", "mention", "reply":
            if let postId = userInfo["postId"] as? String {
                activeDeepLink = .post(postId: postId)
            }
            
        case "message":
            if let conversationId = userInfo["conversationId"] as? String {
                activeDeepLink = .conversation(conversationId: conversationId)
            }
            
        default:
            print("⚠️ Unknown notification type: \(type)")
        }
    }
    
    /// Handle deep link from URL scheme (amenapp://...)
    func handleDeepLink(url: URL) {
        print("🔗 Handling deep link URL: \(url)")
        
        let components = URLComponents(url: url, resolvingAgainstBaseURL: true)
        guard let host = components?.host else { return }
        
        switch host {
        case "post":
            if let postId = components?.queryItems?.first(where: { $0.name == "id" })?.value {
                activeDeepLink = .post(postId: postId)
            }
            
        case "profile":
            if let userId = components?.queryItems?.first(where: { $0.name == "id" })?.value {
                activeDeepLink = .profile(userId: userId)
            }
            
        case "conversation":
            if let conversationId = components?.queryItems?.first(where: { $0.name == "id" })?.value {
                activeDeepLink = .conversation(conversationId: conversationId)
            }
            
        default:
            print("⚠️ Unknown deep link host: \(host)")
        }
    }
    
    /// Clear active deep link after navigation
    func clearDeepLink() {
        activeDeepLink = nil
    }
}

enum NotificationDeepLink: Equatable {
    case profile(userId: String)
    case post(postId: String)
    case conversation(conversationId: String)
    
    var navigationPath: String {
        switch self {
        case .profile(let userId):
            return "profile_\(userId)"
        case .post(let postId):
            return "post_\(postId)"
        case .conversation(let conversationId):
            return "conversation_\(conversationId)"
        }
    }
}

// MARK: - App Delegate Integration Helper

class NotificationAppDelegateHelper {
    
    /// Call this from your AppDelegate's didReceiveRemoteNotification
    static func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) {
        Task { @MainActor in
            NotificationDeepLinkHandler.shared.handleNotificationTap(userInfo: userInfo)
        }
    }
    
    /// Call this from your SceneDelegate's scene(_:openURLContexts:)
    static func handleURL(_ url: URL) {
        Task { @MainActor in
            NotificationDeepLinkHandler.shared.handleDeepLink(url: url)
        }
    }
}
