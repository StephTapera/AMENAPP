import Foundation
import UIKit

// MARK: - PUBLIC INTERFACE

/// Share destinations for AMEN Story/social card sharing.
/// Named `StoryShareTarget` to avoid collision with the existing `ShareDestination`
/// type in `ShareSheet.swift` (which routes posts within the AMEN community feed).
enum StoryShareTarget: CaseIterable {
    case instagramStory
    case facebookStory
    case messages
    case whatsapp
    case copyLink
    case systemSheet
}

/// The content bundle passed to ShareService for story-card sharing.
struct ShareContent {
    let post: Post
    /// Override pull quote; falls back to `post.content` if nil.
    let pullQuote: String?
    /// Override verse reference; falls back to `post.verseReference` if nil.
    let verseRef: String?
    /// Caption text for messaging destinations.
    let caption: String?
    /// Pre-resolved author avatar. Pass nil to use initials fallback.
    let authorAvatar: UIImage?

    init(
        post: Post,
        pullQuote: String? = nil,
        verseRef: String? = nil,
        caption: String? = nil,
        authorAvatar: UIImage? = nil
    ) {
        self.post = post
        self.pullQuote = pullQuote
        self.verseRef = verseRef
        self.caption = caption
        self.authorAvatar = authorAvatar
    }

    /// Canonical public URL for this post.
    var postURL: URL {
        URL(string: "https://amen.app/post/\(post.firestoreId)")!
    }
}
