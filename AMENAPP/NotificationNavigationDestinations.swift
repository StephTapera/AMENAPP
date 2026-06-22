//
//  NotificationNavigationDestinations.swift
//  AMENAPP
//
//  Navigation destination enum for the Notifications NavigationStack.
//  These types are pushed onto `navigationPath` when the user taps a row
//  inside the Notifications tab. Cross-tab routes go through NotificationDeepLinkRouter.
//

import SwiftUI

// MARK: - Navigation Destinations Namespace

struct NotificationNavigationDestinations {
    enum NotificationDestination: Hashable {
        case post(postId: String)
        /// Post with a target comment — CommentsView should scroll to and highlight `commentId`.
        case postWithComment(postId: String, commentId: String)
        case profile(userId: String)
        case prayer(prayerId: String)
        case churchNote(noteId: String)
        case conversation(conversationId: String)

        var id: String {
            switch self {
            case .post(let postId):
                return "post_\(postId)"
            case .postWithComment(let postId, let commentId):
                return "post_\(postId)_comment_\(commentId)"
            case .profile(let userId):
                return "profile_\(userId)"
            case .prayer(let prayerId):
                return "prayer_\(prayerId)"
            case .churchNote(let noteId):
                return "churchNote_\(noteId)"
            case .conversation(let conversationId):
                return "conversation_\(conversationId)"
            }
        }
    }
}
