//
//  FeedItem.swift
//  AMENAPP
//
//  Unified content container model. A single FeedItem can represent any
//  content type (post, prayer, testimony, church note, repost/quote) and
//  appear identically across every surface:
//    - Home feed
//    - Profile
//    - Saved posts
//    - Reply chains
//    - Quote context
//    - Notification deep links
//    - Moderation review queue
//    - Search results
//
//  This separates "what the content IS" from "how it appears" — matching
//  the Threads engineering lesson about first-class conversation objects.
//
//  Adoption path: new features use FeedItem. Existing PostCard stays as-is.
//  Over time, swap PostCard's `post: Post?` for `item: FeedItem`.

import Foundation
import FirebaseFirestore

// MARK: - Prayer Model Stub (temporary until Prayer model is properly defined)

struct Prayer: Identifiable {
    let id: String?
    let userId: String?
    let prayerText: String?
    let timestamp: Date?
}

// MARK: - FeedItem

indirect enum FeedItem: Identifiable {

    case post(Post)
    case prayer(Prayer)
    case testimony(Testimony)
    case repost(RepostWrapper)
    case quote(QuoteWrapper)

    // MARK: - Identifiable

    var id: String {
        switch self {
        case .post(let p):       return "post_\(p.firestoreId)"
        case .prayer(let p):     return "prayer_\(p.id ?? UUID().uuidString)"
        case .testimony(let t):  return "testimony_\(t.id ?? UUID().uuidString)"
        case .repost(let r):     return "repost_\(r.id)"
        case .quote(let q):      return "quote_\(q.id)"
        }
    }

    // MARK: - Author

    var authorId: String? {
        switch self {
        case .post(let p):       return p.authorId
        case .prayer(let p):     return p.userId
        case .testimony(let t):  return t.userId
        case .repost(let r):     return r.repostedByUserId
        case .quote(let q):      return q.authorId
        }
    }

    var authorName: String {
        switch self {
        case .post(let p):       return p.authorName
        case .prayer(let p):     return p.authorName ?? "Anonymous"
        case .testimony(let t):  return t.authorDisplayName
        case .repost(let r):     return r.repostedByName
        case .quote(let q):      return q.authorName
        }
    }

    // MARK: - Timestamp

    var createdAt: Date? {
        switch self {
        case .post(let p):       return p.createdAt
        case .prayer(let p):     return p.createdAt
        case .testimony(let t):  return t.createdAt.dateValue()
        case .repost(let r):     return r.repostedAt
        case .quote(let q):      return q.createdAt
        }
    }

    // MARK: - Text preview (for notifications, search, saved context)

    var textPreview: String {
        switch self {
        case .post(let p):       return String(p.content.prefix(200))
        case .prayer(let p):     return String((p.content ?? "").prefix(200))
        case .testimony(let t):  return String(t.content.prefix(200))
        case .repost(let r):     return r.original.textPreview
        case .quote(let q):      return String(q.quoteText.prefix(200))
        }
    }

    // MARK: - Surface context

    /// The canonical content type label used in moderation, analytics, and UI
    var contentTypeName: String {
        switch self {
        case .post:       return "post"
        case .prayer:     return "prayer"
        case .testimony:  return "testimony"
        case .repost:     return "repost"
        case .quote:      return "quote"
        }
    }

    /// Whether this item can appear in the public home feed
    var isPublicFeedEligible: Bool {
        switch self {
        case .post(let p):       return p.visibility == .everyone || p.visibility == nil
        case .prayer(let p):     return p.isPublic ?? false
        case .testimony:         return true // Testimonies are public by default
        case .repost:            return true
        case .quote:             return true
        }
    }

    /// The underlying Firestore document ID used for reactions, comments, reports
    var firestoreId: String {
        switch self {
        case .post(let p):       return p.firestoreId
        case .prayer(let p):     return p.id ?? ""
        case .testimony(let t):  return t.id ?? ""
        case .repost(let r):     return r.id
        case .quote(let q):      return q.id
        }
    }

    // MARK: - Moderation

    var isFlagged: Bool {
        switch self {
        case .post(let p):       return p.flaggedForReview ?? false
        case .prayer:            return false
        case .testimony:         return false // Testimonies use reportCount instead
        case .repost:            return false
        case .quote:             return false
        }
    }
}

// MARK: - Repost Wrapper

struct RepostWrapper: Identifiable {
    let id: String
    let original: FeedItem
    let repostedByUserId: String
    let repostedByName: String
    let repostedAt: Date

    init(id: String = UUID().uuidString,
         original: FeedItem,
         repostedByUserId: String,
         repostedByName: String,
         repostedAt: Date = Date()) {
        self.id = id
        self.original = original
        self.repostedByUserId = repostedByUserId
        self.repostedByName = repostedByName
        self.repostedAt = repostedAt
    }
}

// MARK: - Quote Wrapper

struct QuoteWrapper: Identifiable {
    let id: String
    let original: FeedItem
    let quoteText: String
    let authorId: String
    let authorName: String
    let createdAt: Date

    init(id: String = UUID().uuidString,
         original: FeedItem,
         quoteText: String,
         authorId: String,
         authorName: String,
         createdAt: Date = Date()) {
        self.id = id
        self.original = original
        self.quoteText = quoteText
        self.authorId = authorId
        self.authorName = authorName
        self.createdAt = createdAt
    }
}

// MARK: - Post convenience init (bridges existing Post model)

extension FeedItem {
    /// Build a FeedItem from a Post, choosing the correct case automatically.
    static func from(_ post: Post) -> FeedItem {
        if post.isRepost {
            // Wrap as repost if we have the repost metadata
            return .post(post) // PostCard already handles isRepost display
        }
        return .post(post)
    }

    /// Convert an array of Posts to FeedItems for use in unified surfaces
    static func from(_ posts: [Post]) -> [FeedItem] {
        posts.map { .from($0) }
    }
}

// MARK: - Prayer stub (partial — extend as Prayer model is typed)

extension Prayer {
    var authorName: String? { nil }     // override when Prayer gains displayName
    var isPublic: Bool? { true }
    var content: String? { prayerText }
    var createdAt: Date? { timestamp }
}
