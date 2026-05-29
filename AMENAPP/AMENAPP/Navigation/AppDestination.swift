// AppDestination.swift
// AMENAPP
//
// Canonical navigation destination enum. Every external entry point — Siri shortcuts,
// Spotlight, URL schemes (amen://, amenapp://, https://amenapp.com/), Home Screen quick
// actions, Live Activity taps, widgets — resolves to one of these cases before any
// routing code runs.
//
// Usage:
//   AppNavigationRouter.shared.navigate(to: .newPost)
//   AppNavigationRouter.shared.navigate(to: AppDestination(url: url))

import Foundation

// MARK: - AppDestination

/// Canonical set of navigable destinations in the AMEN app.
/// Add new cases here when new surfaces or deep-link hosts are introduced.
enum AppDestination: Hashable, Sendable {

    // ── Tabs ──────────────────────────────────────────────────────────────
    case home
    case discovery
    case messages
    case resources                          // Resources tab (Church Notes, Prayer, Find Church)
    case activity                           // Notifications tab
    case profile

    // ── Composer sheets ───────────────────────────────────────────────────
    case newPost
    case continueDraft                      // Restore latest draft in composer
    case testimony                          // Testimony composer
    case prayerNew                          // Prayer request composer

    // ── Feature sheets / sub-flows ────────────────────────────────────────
    case askBerean(question: String? = nil) // Open Berean AI; optional pre-filled question
    case findChurch
    case churchNotes
    case reflection                         // Calm / quiet reflection mode
    case verseOfDay

    // ── Content detail (require IDs) ─────────────────────────────────────
    case post(id: String, highlightCommentId: String? = nil)
    case userProfile(userId: String)
    case church(churchId: String)
    case conversation(conversationId: String, highlightMessageId: String? = nil)
    case prayer(prayerId: String)
    case churchNote(noteId: String)
    case groupJoinLink(token: String)

    // ── Search ────────────────────────────────────────────────────────────
    case search(query: String? = nil)

    // ── Settings ─────────────────────────────────────────────────────────
    case settings(section: String? = nil)

    // ── Berean Spotlight contexts ─────────────────────────────────────────
    case bereanWithVerse(reference: String)
    case bereanWithSession(sessionId: String)

    // MARK: Equatable / Hashable (manual for cases with associated values)

    static func == (lhs: AppDestination, rhs: AppDestination) -> Bool {
        switch (lhs, rhs) {
        case (.home, .home), (.discovery, .discovery), (.messages, .messages),
             (.resources, .resources), (.activity, .activity), (.profile, .profile),
             (.newPost, .newPost), (.continueDraft, .continueDraft),
             (.testimony, .testimony), (.prayerNew, .prayerNew),
             (.findChurch, .findChurch), (.churchNotes, .churchNotes),
             (.reflection, .reflection), (.verseOfDay, .verseOfDay):
            return true
        case let (.askBerean(q1), .askBerean(q2)):          return q1 == q2
        case let (.post(id1, c1), .post(id2, c2)):          return id1 == id2 && c1 == c2
        case let (.userProfile(u1), .userProfile(u2)):      return u1 == u2
        case let (.church(c1), .church(c2)):                return c1 == c2
        case let (.conversation(c1, m1), .conversation(c2, m2)): return c1 == c2 && m1 == m2
        case let (.prayer(p1), .prayer(p2)):                return p1 == p2
        case let (.churchNote(n1), .churchNote(n2)):        return n1 == n2
        case let (.groupJoinLink(t1), .groupJoinLink(t2)):  return t1 == t2
        case let (.search(q1), .search(q2)):                return q1 == q2
        case let (.settings(s1), .settings(s2)):            return s1 == s2
        case let (.bereanWithVerse(r1), .bereanWithVerse(r2)): return r1 == r2
        case let (.bereanWithSession(s1), .bereanWithSession(s2)): return s1 == s2
        default: return false
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(analyticsLabel)
    }
}

// MARK: - URL Parsing

extension AppDestination {

    /// Attempt to create an `AppDestination` from a deep-link URL.
    ///
    /// Supported schemes:
    ///   `amen://`, `amenapp://`, `com.amenapp://`, `https://amenapp.com/`
    ///
    /// Returns `nil` when the URL is not a recognised AMEN deep link or when a
    /// required identifier is missing / contains unsafe characters.
    init?(url: URL) {
        let scheme  = url.scheme?.lowercased() ?? ""
        let host    = url.host ?? ""
        let path    = url.pathComponents.filter { $0 != "/" }
        let query   = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        func q(_ name: String) -> String? { query.first(where: { $0.name == name })?.value }

        // Universal links — treat path as the route
        if scheme == "https" || scheme == "http" {
            guard host.hasSuffix("amenapp.com") || host.hasSuffix("amen.app") else { return nil }
            // https://amenapp.com/post/abc123
            guard let first = path.first else { return nil }
            switch first {
            case "post":
                guard let id = path.dropFirst().first, Self.isValidId(id) else { return nil }
                self = .post(id: id, highlightCommentId: q("comment"))
            case "profile":
                guard let id = path.dropFirst().first, Self.isValidId(id) else { return nil }
                self = .userProfile(userId: id)
            case "conversation":
                guard let id = path.dropFirst().first, Self.isValidId(id) else { return nil }
                self = .conversation(conversationId: id, highlightMessageId: q("message"))
            case "prayer":
                guard let id = path.dropFirst().first, Self.isValidId(id) else { return nil }
                self = .prayer(prayerId: id)
            case "church-note":
                guard let id = path.dropFirst().first, Self.isValidId(id) else { return nil }
                self = .churchNote(noteId: id)
            case "church":
                guard let id = path.dropFirst().first, Self.isValidId(id) else { return nil }
                self = .church(churchId: id)
            case "group" where path.dropFirst().first == "join":
                guard let token = q("token"), !token.isEmpty else { return nil }
                self = .groupJoinLink(token: token)
            case "access":
                // Delegate to access-pass router; not handled here
                return nil
            default:
                return nil
            }
            return
        }

        let isAmenScheme    = scheme == "amen"
        let isAmenAppScheme = scheme == "amenapp" || scheme == "com.amenapp"
        guard isAmenScheme || isAmenAppScheme else { return nil }

        switch host {

        // ── Content ───────────────────────────────────────────────────────
        case "post":
            guard let id = path.first, Self.isValidId(id) else { return nil }
            self = .post(id: id, highlightCommentId: q("comment") ?? q("commentId"))

        case "user", "profile":
            guard let id = path.first, Self.isValidId(id) else { return nil }
            self = .userProfile(userId: id)

        case "church":
            guard let id = path.first, Self.isValidId(id) else { return nil }
            self = .church(churchId: id)

        case "conversation", "messages" where !path.isEmpty:
            guard let id = path.first, Self.isValidId(id) else { return nil }
            self = .conversation(conversationId: id, highlightMessageId: q("message") ?? q("messageId"))

        case "messages":
            self = .messages

        case "prayer" where !path.isEmpty && path.first == "new":
            self = .prayerNew

        case "prayer" where path.isEmpty || path.first == nil:
            self = .resources         // Prayer lives in Resources tab

        case "prayer":
            // amen://prayer/{prayerId}
            guard let id = path.first, Self.isValidId(id) else { return nil }
            self = .prayer(prayerId: id)

        case "prayer-composer":
            self = .prayerNew

        case "church-note":
            guard let id = path.first, Self.isValidId(id) else { return nil }
            self = .churchNote(noteId: id)

        case "group" where path.first == "join":
            guard let token = q("token"), !token.isEmpty else { return nil }
            self = .groupJoinLink(token: token)

        // ── Tabs ──────────────────────────────────────────────────────────
        case "home":
            self = .home

        case "notifications":
            self = .activity

        case "discover", "search" where host == "discover":
            self = .discovery

        case "search":
            self = .search(query: q("q"))

        case "settings":
            self = .settings(section: path.first)

        // ── Berean ────────────────────────────────────────────────────────
        case "berean":
            if let verse = q("verse") {
                self = .bereanWithVerse(reference: verse)
            } else if let session = q("session") {
                self = .bereanWithSession(sessionId: session)
            } else {
                self = .askBerean(question: q("q"))
            }

        // ── Faith features ────────────────────────────────────────────────
        case "find-church":
            self = .findChurch

        case "church-notes":
            self = .churchNotes

        case "reflection":
            self = .reflection

        case "verse":
            self = .verseOfDay

        case "category":
            // amen://category/prayer — treat as resources tab
            self = .resources

        case "comment":
            // amen://comment?postId=…  → open the post
            guard let postId = q("postId"), Self.isValidId(postId) else { return nil }
            self = .post(id: postId, highlightCommentId: q("commentId"))

        case "chat":
            guard let threadId = q("threadId"), Self.isValidId(threadId) else { return nil }
            self = .conversation(conversationId: threadId, highlightMessageId: nil)

        default:
            return nil
        }
    }

    // MARK: - Auth requirement

    /// Whether the destination requires an authenticated user.
    var requiresAuth: Bool {
        switch self {
        case .messages, .newPost, .continueDraft, .testimony, .prayerNew,
             .askBerean, .findChurch, .churchNotes, .reflection,
             .prayer, .churchNote, .conversation, .groupJoinLink,
             .userProfile, .post, .church,
             .bereanWithVerse, .bereanWithSession, .activity, .profile, .resources:
            return true
        case .home, .discovery, .search, .settings, .verseOfDay:
            return false
        }
    }

    // MARK: - Target tab index

    /// The tab that this destination primarily lives in.
    /// Tab layout: 0=Home, 1=Discovery, 2=Messages, 3=Resources, 4=Notifications, 5=Profile
    var targetTab: Int {
        switch self {
        case .home, .newPost, .continueDraft, .testimony, .post, .userProfile, .verseOfDay:
            return 0
        case .discovery, .search:
            return 1
        case .messages, .conversation, .groupJoinLink:
            return 2
        case .resources, .findChurch, .churchNotes, .reflection,
             .prayer, .prayerNew, .churchNote, .church:
            return 3
        case .activity:
            return 4
        case .profile, .settings:
            return 5
        case .askBerean, .bereanWithVerse, .bereanWithSession:
            return 0  // Berean sheet opens over whatever tab is active
        }
    }

    // MARK: - Analytics label

    var analyticsLabel: String {
        switch self {
        case .home:                             return "home"
        case .discovery:                        return "discovery"
        case .messages:                         return "messages"
        case .resources:                        return "resources"
        case .activity:                         return "activity"
        case .profile:                          return "profile"
        case .newPost:                          return "newPost"
        case .continueDraft:                    return "continueDraft"
        case .testimony:                        return "testimony"
        case .prayerNew:                        return "prayerNew"
        case .askBerean(let q):                 return "askBerean/\(q ?? "")"
        case .findChurch:                       return "findChurch"
        case .churchNotes:                      return "churchNotes"
        case .reflection:                       return "reflection"
        case .verseOfDay:                       return "verseOfDay"
        case .post(let id, _):                  return "post/\(id)"
        case .userProfile(let id):              return "userProfile/\(id)"
        case .church(let id):                   return "church/\(id)"
        case .conversation(let id, _):          return "conversation/\(id)"
        case .prayer(let id):                   return "prayer/\(id)"
        case .churchNote(let id):               return "churchNote/\(id)"
        case .groupJoinLink(let token):         return "groupJoinLink/\(token.prefix(8))"
        case .search(let q):                    return "search/\(q ?? "")"
        case .settings(let s):                  return "settings/\(s ?? "root")"
        case .bereanWithVerse(let ref):         return "bereanVerse/\(ref)"
        case .bereanWithSession(let id):        return "bereanSession/\(id)"
        }
    }

    // MARK: - Helpers

    /// Validates Firestore-safe document IDs (letters, digits, underscore, hyphen; 1–128 chars).
    static func isValidId(_ id: String) -> Bool {
        let pattern = "^[a-zA-Z0-9_-]{1,128}$"
        return id.range(of: pattern, options: .regularExpression) != nil
    }
}
