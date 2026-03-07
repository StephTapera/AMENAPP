//
//  CommentService.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//
//  Service for managing comments and replies on posts
//  Using Realtime Database for instant sync and accurate counts
//

import Foundation
import FirebaseDatabase
import FirebaseAuth
import FirebaseFirestore
import Combine
import UIKit

// MARK: - Comment Service

@MainActor
class CommentService: ObservableObject {
    static let shared = CommentService()
    
    @Published var comments: [String: [Comment]] = [:]  // postId -> comments
    @Published var commentReplies: [String: [Comment]] = [:]  // commentId -> replies
    @Published var isLoading = false
    @Published var error: String?
    
    private let firebaseManager = FirebaseManager.shared
    private let userService = UserService()
    // Lazy to avoid accessing Database.database() before AppDelegate sets isPersistenceEnabled.
    nonisolated(unsafe) private lazy var database: Database = Database.database()
    private var ref: DatabaseReference {
        database.reference()
    }
    nonisolated(unsafe) private var listenerPaths: [String: DatabaseHandle] = [:]
    
    // P0-1 FIX: Prevent duplicate comment creation
    private var inFlightCommentRequests: Set<String> = []
    
    // P0-2 FIX: Track optimistic comments for replacement.
    // Key: clientRequestId (written into RTDB alongside the comment).
    // Value: the local tempId used for UI dedup.
    // Using clientRequestId instead of content.hashValue avoids false matches
    // when two comments have identical content.
    private var optimisticComments: [String: String] = [:]  // clientRequestId -> tempId
    
    private init() {}

    // MARK: - Content Normalization

    /// Trims whitespace and collapses internal runs of whitespace to a single space.
    /// Used for dedup keys and moderation — never for display.
    private func normalizedContent(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    /// Deterministic, stable in-flight request key. Does NOT use hashValue
    /// (which is not stable across processes and can collide on different content).
    private func makeRequestId(postId: String, userId: String, content: String) -> String {
        "\(postId)|\(userId)|\(normalizedContent(content).lowercased())"
    }

    deinit {
        // Guard: if listenerPaths is empty the lazy `database` was never accessed,
        // so skip cleanup to avoid triggering lazy init during teardown.
        guard !listenerPaths.isEmpty else { return }

        // Remove all Realtime DB handles synchronously.
        // Firebase DatabaseReference.removeObserver(withHandle:) is thread-safe.
        let dbRef = database.reference()
        for (postId, handle) in listenerPaths {
            dbRef.child("postInteractions").child(postId).child("comments").removeObserver(withHandle: handle)
        }
    }
    
    // MARK: - Helper Types
    
    struct TimeoutError: Error {
        let operation: String
    }
    
    // MARK: - Comment Permissions
    
    /// Check if user can comment on a post
    func canComment(postId: String, post: Post) async -> Bool {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return false
        }
        
        // Post author can always comment
        if post.authorId == currentUserId {
            return true
        }
        
        // Check comment permissions
        let permissions = post.commentPermissions ?? .everyone
        
        switch permissions {
        case .everyone:
            return true
            
        case .following:
            // "Following only": current user must follow the post author to comment.
            // isFollowing(userId:) returns true when current user is following that userId.
            return await FollowService.shared.isFollowing(userId: post.authorId)

        case .mentioned:
            // "Mentioned only": current user must be mentioned in the post by @username.
            // We compare @username (not UID) because post text uses handles, not auth UIDs.
            guard let profile = try? await userService.fetchUserProfile(userId: currentUserId),
                  !profile.username.isEmpty else {
                return false
            }
            let mentions = extractMentions(from: post.content)
            return mentions.contains { $0.lowercased() == "@\(profile.username.lowercased())" }
            
        case .off:
            return false
        }
    }
    
    private func extractMentions(from text: String) -> [String] {
        let pattern = "@[a-zA-Z0-9_]+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        
        return matches.compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range])
        }
    }
    
    // MARK: - Create Comment
    
    /// Add a comment to a post
    func addComment(
        postId: String,
        content: String,
        mentionedUserIds: [String]? = nil,
        post: Post? = nil  // Optional post object (avoid refetch if already available)
    ) async throws -> Comment {
        dlog("💬 Adding comment to post: \(postId)")

        guard let userId = firebaseManager.currentUser?.uid else {
            throw NSError(domain: "CommentService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }

        // ✅ CHECK RATE LIMIT FOR NEW ACCOUNTS
        let rateLimitCheck = await NewAccountRestrictionService.shared.canComment(userId: userId)
        guard rateLimitCheck.allowed else {
            let reason = rateLimitCheck.reason ?? "Comment limit reached. Please try again later."
            dlog("⚠️ Comment rate limit exceeded: \(reason)")
            throw NSError(domain: "CommentService", code: -11,
                         userInfo: [NSLocalizedDescriptionKey: reason])
        }

        // 🛡️ CHECK ANTI-HARASSMENT RESTRICTION
        if let restriction = try? await AntiHarassmentEngine.shared.checkRestriction(
            userId: userId,
            type: .commenting
        ), restriction.isRestricted {
            let endsAt = restriction.endsAt.map {
                DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short)
            } ?? "soon"
            dlog("⛔ Commenting restricted for user \(userId) until \(endsAt)")
            throw NSError(
                domain: "CommentService",
                code: -12,
                userInfo: [NSLocalizedDescriptionKey: "Your commenting ability is temporarily restricted until \(endsAt) due to a community guidelines violation."]
            )
        }

        // 🛡️ LAYER 0: Synchronous local content guard (offline, zero-latency)
        // Runs BEFORE any async checks — instant hard block for slurs, profanity,
        // harassment, sexual content, hate speech, violence.
        let localGuardResult = LocalContentGuard.check(content)
        if localGuardResult.isBlocked {
            dlog("⛔ [LocalContentGuard] Comment blocked: \(localGuardResult.category.rawValue)")
            throw NSError(
                domain: "CommentService",
                code: -13,
                userInfo: [NSLocalizedDescriptionKey: localGuardResult.userMessage]
            )
        }

        // P0-1 FIX: Prevent duplicate in-flight requests.
        // makeRequestId uses normalized content (not hashValue) for a stable, collision-resistant key.
        let requestId = makeRequestId(postId: postId, userId: userId, content: content)
        guard !inFlightCommentRequests.contains(requestId) else {
            dlog("⚠️ [P0-1] Duplicate comment request blocked: \(requestId)")
            throw NSError(domain: "CommentService", code: -10, 
                         userInfo: [NSLocalizedDescriptionKey: "Comment already being submitted"])
        }
        
        inFlightCommentRequests.insert(requestId)
        defer { inFlightCommentRequests.remove(requestId) }
        
        // ============================================================================
        // ✅ PRIVACY CHECK: Verify user can comment on this post
        // ============================================================================
        dlog("🔒 Checking comment permissions for post: \(postId)")
        
        // Fetch post if not provided
        let postData: Post
        if let providedPost = post {
            postData = providedPost
        } else {
            // Fetch post from Firestore
            let db = Firestore.firestore()
            let postDoc = try await db.collection("posts").document(postId).getDocument()
            guard let post = try? postDoc.data(as: Post.self) else {
                throw NSError(domain: "CommentService", code: -3,
                             userInfo: [NSLocalizedDescriptionKey: "Post not found"])
            }
            postData = post
        }
        
        // Check comment permissions using TrustByDesignService
        let canCommentOnPost = try await TrustByDesignService.shared.canComment(
            userId: userId,
            on: postId,
            authorId: postData.authorId,
            postPermission: postData.commentPermissions.map { perm in
                // Map Post.CommentPermissions to CommentPermissionLevel
                switch perm {
                case .everyone: return .everyone
                case .following: return .followersOnly
                case .mentioned: return .mutualsOnly  // Map "mentioned only" to mutuals
                case .off: return .nobody
                }
            }
        )
        
        if !canCommentOnPost {
            dlog("❌ Comment permission denied for post: \(postId)")
            throw NSError(domain: "CommentService", code: -4,
                         userInfo: [NSLocalizedDescriptionKey: "You don't have permission to comment on this post"])
        }
        
        dlog("✅ Comment permission granted")

        // ⚡ FAST PATH: Only fetch user profile on the critical path.
        // Moderation, safety, and AI checks run AFTER the write (see fire-and-forget task below).
        let userProfile: UserModel?
        do {
            userProfile = try await userService.fetchUserProfile(userId: userId)
        } catch {
            dlog("⚠️ Failed to fetch user profile: \(error)")
            userProfile = nil
        }

        dlog("✅ Comment passed fast-path checks")

        // Get username and profile image from profile fetch
        let authorUsername: String
        let authorProfileImageURL: String?
        if let profile = userProfile {
            authorUsername = profile.username
            authorProfileImageURL = profile.profileImageURL
            dlog("✅ Using username: @\(authorUsername)")
        } else {
            authorUsername = "user\(userId.prefix(8))"
            authorProfileImageURL = nil
            dlog("⚠️ Using fallback username")
        }

        // ⚡ Immediate haptic feedback BEFORE database write
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()

        // Assign a tempId and clientRequestId for listener dedup.
        // We do NOT insert optimistically into comments[postId]. The RTDB listener fires
        // within milliseconds (local persistence) and is the sole writer of comments[postId],
        // eliminating concurrent-mutation crashes.
        let tempId = UUID().uuidString
        let clientRequestId = UUID().uuidString
        optimisticComments[clientRequestId] = tempId

        // P1-3 FIX: Write to database with retry logic and timeout
        let interactionsService = PostInteractionsService.shared
        var commentId: String?
        var retryCount = 0
        let maxRetries = 3
        var lastError: Error?
        
        while retryCount < maxRetries {
            do {
                // Attempt write with 10 second timeout
                commentId = try await withTimeout(seconds: 10) {
                    try await interactionsService.addComment(
                        postId: postId,
                        content: content,
                        authorInitials: self.firebaseManager.currentUser?.displayName?.prefix(2).uppercased() ?? "??",
                        authorUsername: authorUsername,
                        authorProfileImageURL: authorProfileImageURL,
                        clientRequestId: clientRequestId
                    )
                }
                
                dlog("✅ [P1-3] Comment created with ID: \(commentId!) (attempt \(retryCount + 1))")
                break // Success, exit retry loop
                
            } catch {
                lastError = error
                retryCount += 1
                
                if retryCount < maxRetries {
                    let backoffDelay = Double(retryCount) * 1.0 // 1s, 2s, 3s
                    dlog("⚠️ [P1-3] Comment submission failed (attempt \(retryCount)/\(maxRetries)), retrying in \(backoffDelay)s...")
                    try await Task.sleep(nanoseconds: UInt64(backoffDelay * 1_000_000_000))
                } else {
                    dlog("❌ [P1-3] All \(maxRetries) attempts failed")
                }
            }
        }
        
        // If all retries failed, clean up and throw
        guard let finalCommentId = commentId else {
            optimisticComments.removeValue(forKey: clientRequestId)
            
            NotificationCenter.default.post(
                name: Notification.Name("commentFailed"),
                object: nil,
                userInfo: ["tempId": tempId, "postId": postId, "error": lastError!]
            )
            
            throw lastError!
        }
        
        dlog("✅ Comment created with ID: \(finalCommentId)")
        
        // ✅ RECORD RATE LIMIT ACTION
        await NewAccountRestrictionService.shared.recordAction(.comment, userId: userId)

        // P0-2: Clean up optimistic tracking — the RTDB listener will replace the
        // optimistic entry (matched by clientRequestId) when the real write fires.
        optimisticComments.removeValue(forKey: clientRequestId)
        dlog("✅ Comment written to RTDB (ID: \(finalCommentId)); listener will replace optimistic \(tempId)")

        // Final comment with real ID
        let finalComment = Comment(
            id: finalCommentId,
            postId: postId,
            authorId: userId,
            authorName: firebaseManager.currentUser?.displayName ?? "Unknown User",
            authorUsername: authorUsername,
            authorInitials: firebaseManager.currentUser?.displayName?.prefix(2).uppercased() ?? "??",
            authorProfileImageURL: authorProfileImageURL,
            content: content,
            createdAt: Date(),
            updatedAt: Date(),
            amenCount: 0,
            replyCount: 0,
            amenUserIds: [],
            parentCommentId: nil,
            mentionedUserIds: mentionedUserIds
        )

        // ⚡ FIRE-AND-FORGET: Post-write moderation pipeline.
        // Runs AFTER the RTDB write — user sees their comment immediately.
        // If violations are found the comment is flagged/deleted server-side
        // without blocking the original submission.
        let capturedContent = content
        let capturedPostId = postId
        let capturedPostAuthorId = postData.authorId
        let capturedUserId = userId
        let capturedFinalCommentId = finalCommentId
        Task.detached(priority: .utility) {
            let signals = AuthenticitySignals(
                typedCharacters: capturedContent.count,
                pastedCharacters: 0,
                typedVsPastedRatio: 1.0,
                largestPasteLength: 0,
                pasteEventCount: 0,
                typingDurationSeconds: 0,
                hasLargePaste: false
            )

            async let moderationTask: ModerationDecision = {
                return try await ContentModerationService.moderateContent(
                    text: capturedContent,
                    category: .comment,
                    signals: signals
                )
            }()

            async let safetyCheckTask: CommentSafetySystem.SafetyCheckResult? = {
                do {
                    return try await CommentSafetySystem.shared.checkCommentSafety(
                        content: capturedContent,
                        postId: capturedPostId,
                        postAuthorId: capturedPostAuthorId,
                        commenterId: capturedUserId
                    )
                } catch {
                    return nil
                }
            }()

            async let aiDetectionTask: AIContentDetectionResult = {
                return await AIContentDetectionService.shared.detectAIContent(capturedContent)
            }()

            guard let (moderationResult, safetyResult, aiDetectionResult) = try? await (moderationTask, safetyCheckTask, aiDetectionTask) else {
                return
            }

            // Read @MainActor-isolated properties on the main actor, then capture as plain values.
            let (moderationShouldBlock, moderationReasons, safetyIsBlocking, isAIGenerated) =
                await MainActor.run {
                    (
                        moderationResult.shouldBlock,
                        moderationResult.reasons,
                        safetyResult?.action.isBlocking == true,
                        aiDetectionResult.isAIGenerated
                    )
                }

            // Determine if comment should be removed after the fact
            let shouldRemove = moderationShouldBlock || safetyIsBlocking || isAIGenerated

            if shouldRemove {
                // Remove the comment from RTDB (silent enforcement)
                let dbRef = Database.database().reference()
                    .child("postInteractions")
                    .child(capturedPostId)
                    .child("comments")
                    .child(capturedFinalCommentId)
                do {
                    try await dbRef.removeValue()
                    dlog("🛡️ [Post-write] Comment \(capturedFinalCommentId) removed by async moderation pipeline")
                } catch {
                    dlog("⚠️ [Post-write] Failed to remove flagged comment: \(error)")
                }

                // Notify UI on main actor so caller can reflect removal if visible
                await MainActor.run {
                    if moderationShouldBlock {
                        ModerationToastManager.shared.show(reasons: moderationReasons)
                    }
                    NotificationCenter.default.post(
                        name: Notification.Name("commentRemovedByModeration"),
                        object: nil,
                        userInfo: ["commentId": capturedFinalCommentId, "postId": capturedPostId]
                    )
                }
            }
        }

        // ⚡ FIRE-AND-FORGET: Mention notifications (don't block UI).
        // Plain Task (not Task.detached) preserves @MainActor context safely.
        let mentionUsernames = extractMentionUsernames(from: content)
        if !mentionUsernames.isEmpty {
            Task { [weak self] in
                guard let self = self else { return }
                var mentions: [MentionedUser] = []

                for username in mentionUsernames {
                    do {
                        let userQuery = try await self.firebaseManager.firestore
                            .collection("users")
                            .whereField("username", isEqualTo: username)
                            .limit(to: 1)
                            .getDocuments()

                        if let userDoc = userQuery.documents.first {
                            let mentionUserId = userDoc.documentID
                            let displayName = userDoc.data()["displayName"] as? String ?? username
                            
                            // ✅ PRIVACY CHECK: Verify user can mention this person
                            let canMention = try await TrustByDesignService.shared.canMention(
                                from: userId,
                                mention: mentionUserId
                            )
                            
                            if canMention {
                                mentions.append(MentionedUser(
                                    userId: mentionUserId,
                                    username: username,
                                    displayName: displayName
                                ))
                                dlog("✅ Mention permission granted for @\(username)")
                            } else {
                                dlog("⚠️ Mention permission denied for @\(username) - skipping notification")
                            }
                        }
                    } catch {
                        dlog("⚠️ Failed to resolve @\(username): \(error)")
                    }
                }

                if !mentions.isEmpty {
                    await NotificationService.shared.sendMentionNotifications(
                        mentions: mentions,
                        actorId: userId,
                        actorName: self.firebaseManager.currentUser?.displayName ?? "User",
                        actorUsername: authorUsername,
                        postId: postId,
                        contentType: "comment"
                    )
                }
            }
        }

        return finalComment
    }
    
    // MARK: - Helper: Extract Mentions
    
    private func extractMentionUsernames(from text: String) -> [String] {
        let pattern = "@(\\w+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }
        
        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        
        return matches.compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let usernameRange = match.range(at: 1)
            return nsString.substring(with: usernameRange)
        }
    }
    
    // MARK: - Create Reply
    
    /// Add a reply to a comment (stored as a comment with parentCommentId in Realtime DB)
    func addReply(
        postId: String,
        parentCommentId: String,
        content: String,
        mentionedUserIds: [String]? = nil,
        post: Post? = nil  // ✅ Optional post object to avoid Firestore lookup
    ) async throws -> Comment {
        dlog("↩️ Adding reply to comment: \(parentCommentId)")

        // ✅ Add comment first — moderation runs inside; haptic fires AFTER success
        let comment = try await addComment(postId: postId, content: content, mentionedUserIds: mentionedUserIds, post: post)

        // P1-1 FIX: Set parentCommentId SYNCHRONOUSLY (not fire-and-forget)
        guard let commentId = comment.id else {
            dlog("⚠️ Comment has no ID, cannot set parentCommentId")
            return comment
        }

        // CRITICAL: Update parent BEFORE returning (prevents background race condition)
        let commentRef = ref.child("postInteractions")
            .child(postId)
            .child("comments")
            .child(commentId)
        
        try await commentRef.updateChildValues([
            "parentCommentId": parentCommentId
        ])

        // Haptic fires here — after the write succeeds — not before moderation/auth checks
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        
        dlog("✅ [P1-1] Reply linked to parent: \(parentCommentId) (synchronous)")

        // Create updated comment with parent ID
        var updatedComment = comment
        updatedComment.parentCommentId = parentCommentId

        // Post notification (real-time listener will also update)
        NotificationCenter.default.post(
            name: Notification.Name("newCommentCreated"),
            object: nil,
            userInfo: ["comment": updatedComment, "isReply": true, "parentCommentId": parentCommentId]
        )
        dlog("📬 Posted newCommentCreated notification for reply")

        return updatedComment
    }
    
    // MARK: - Fetch Comments
    
    /// Fetch all comments for a post from Realtime Database
    func fetchComments(for postId: String) async throws -> [Comment] {
        dlog("📥 Fetching comments for post: \(postId)")
        dlog("🔍 [DEBUG] Querying path: postInteractions/\(postId)/comments")
        
        isLoading = true
        defer { isLoading = false }
        
        let interactionsService = PostInteractionsService.shared
        let realtimeComments = await interactionsService.getComments(postId: postId)
        dlog("🔍 [DEBUG] Raw query returned \(realtimeComments.count) comments from RTDB")
        
        // Convert to Comment objects and filter out replies (only get top-level comments)
        var fetchedComments: [Comment] = []
        
        for rtComment in realtimeComments {
            // ✅ Skip replies (these are handled separately)
            guard rtComment.parentCommentId == nil else {
                dlog("⏭️ Skipping reply: \(rtComment.id)")
                continue
            }
            
            // ✅ Use stored username and profile image from RTDB
            let authorUsername: String
            let authorProfileImageURL: String?
            
            if let storedUsername = rtComment.authorUsername, !storedUsername.isEmpty {
                authorUsername = storedUsername
                dlog("✅ Using stored username: @\(authorUsername)")
            } else {
                dlog("⚠️ No stored username, using fallback")
                authorUsername = "user\(rtComment.authorId.prefix(8))"
            }
            
            // ✅ Get profile image URL from RTDB
            authorProfileImageURL = rtComment.authorProfileImageURL
            if let imageURL = authorProfileImageURL {
                dlog("✅ Profile image URL: \(imageURL)")
            }
            
            let comment = Comment(
                id: rtComment.id,
                postId: postId,
                authorId: rtComment.authorId,
                authorName: rtComment.authorName,
                authorUsername: authorUsername,
                authorInitials: rtComment.authorInitials,
                authorProfileImageURL: authorProfileImageURL,  // ✅ Now includes profile image
                content: rtComment.content,
                createdAt: rtComment.timestamp,
                updatedAt: rtComment.timestamp,
                amenCount: rtComment.likes,
                replyCount: 0,
                amenUserIds: [],
                parentCommentId: nil,
                mentionedUserIds: nil
            )
            
            fetchedComments.append(comment)
        }
        
        dlog("✅ Fetched \(fetchedComments.count) top-level comments from Realtime DB")
        
        // Update local cache
        comments[postId] = fetchedComments
        
        return fetchedComments
    }
    
    /// Fetch replies for a specific comment
    func fetchReplies(for commentId: String) async throws -> [Comment] {
        dlog("📥 Fetching replies for comment: \(commentId)")
        
        // ✅ FIXED: First check cache (populated by real-time listener)
        if let cachedReplies = commentReplies[commentId], !cachedReplies.isEmpty {
            dlog("✅ Returning \(cachedReplies.count) cached replies for comment: \(commentId)")
            return cachedReplies
        }
        
        // ✅ If cache is empty, fetch from database
        // This happens when the real-time listener hasn't populated the cache yet
        // or when loading historical data
        dlog("⚠️ No cached replies, fetching from database for comment: \(commentId)")
        
        // We need to find which post this comment belongs to
        // Search through all cached posts' comments to find the parent
        var parentPostId: String?
        for (postId, postComments) in comments {
            if postComments.contains(where: { $0.id == commentId }) {
                parentPostId = postId
                break
            }
        }
        
        guard let postId = parentPostId else {
            dlog("⚠️ Could not find post for comment: \(commentId)")
            return []
        }
        
        // Fetch all comments for the post and filter replies
        let interactionsService = PostInteractionsService.shared
        let allComments = await interactionsService.getComments(postId: postId)
        
        var replies: [Comment] = []
        for rtComment in allComments {
            // Only get replies for this specific comment
            guard rtComment.parentCommentId == commentId else { continue }
            
            let authorUsername: String
            let authorProfileImageURL: String?
            
            if let storedUsername = rtComment.authorUsername, !storedUsername.isEmpty {
                authorUsername = storedUsername
            } else {
                authorUsername = "user\(rtComment.authorId.prefix(8))"
            }
            
            authorProfileImageURL = rtComment.authorProfileImageURL
            
            let reply = Comment(
                id: rtComment.id,
                postId: postId,
                authorId: rtComment.authorId,
                authorName: rtComment.authorName,
                authorUsername: authorUsername,
                authorInitials: rtComment.authorInitials,
                authorProfileImageURL: authorProfileImageURL,
                content: rtComment.content,
                createdAt: rtComment.timestamp,
                updatedAt: rtComment.timestamp,
                amenCount: rtComment.likes,
                replyCount: 0,
                amenUserIds: [],
                parentCommentId: rtComment.parentCommentId,
                mentionedUserIds: nil
            )
            
            replies.append(reply)
        }
        
        // Sort by timestamp
        replies.sort { $0.createdAt < $1.createdAt }
        
        // Update cache
        commentReplies[commentId] = replies
        
        dlog("✅ Fetched \(replies.count) replies from database for comment: \(commentId)")
        return replies
    }
    
    /// Fetch all comments by a specific user
    func fetchUserComments(userId: String, limit: Int = 50) async throws -> [Comment] {
        dlog("📥 Fetching comments for user: \(userId)")
        
        // Would need to query across all posts - not implemented yet
        return []
    }
    
    /// Fetch comments with nested replies
    func fetchCommentsWithReplies(for postId: String) async throws -> [CommentWithReplies] {
        dlog("📥 Fetching comments with replies for post: \(postId)")
        
        // ✅ IMPROVED: Check if real-time listener has already populated the cache
        if let cachedComments = comments[postId], !cachedComments.isEmpty {
            dlog("✅ Using cached comments from real-time listener (\(cachedComments.count) comments)")
            
            var commentsWithReplies: [CommentWithReplies] = []
            
            for comment in cachedComments {
                guard let commentId = comment.id else { continue }
                
                // Get replies from cache (populated by real-time listener)
                let replies = commentReplies[commentId] ?? []
                
                var updatedComment = comment
                updatedComment.replyCount = replies.count
                
                let commentWithReplies = CommentWithReplies(comment: updatedComment, replies: replies)
                commentsWithReplies.append(commentWithReplies)
            }
            
            dlog("✅ Built \(commentsWithReplies.count) comments with replies from cache")
            return commentsWithReplies
        }
        
        // Cache is empty — the real-time listener (started in PostDetailView.task) will
        // populate comments[postId] within milliseconds via the RTDB local cache.
        // Returning [] here is safe: PostDetailView uses the computed property which reads
        // directly from comments[postId], so as soon as the listener fires SwiftUI redraws.
        // This eliminates the N+1 pattern (1 full fetch + N reply fetches per comment).
        dlog("⚠️ Cache empty — listener will populate shortly")
        return []
    }
    
    // MARK: - Update Comment
    
    /// Edit comment content
    func editComment(commentId: String, postId: String, newContent: String) async throws {
        dlog("✏️ Editing comment: \(commentId)")

        let trimmedContent = normalizedContent(newContent)
        guard !trimmedContent.isEmpty else {
            throw NSError(domain: "CommentService", code: -3, userInfo: [NSLocalizedDescriptionKey: "Comment cannot be empty"])
        }
        
        guard let userId = firebaseManager.currentUser?.uid else {
            throw NSError(domain: "CommentService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }

        // 🛡️ LAYER 0: Run the same local content guard as on creation.
        // Prevents a user posting clean content then editing to abusive content.
        let localGuardResult = LocalContentGuard.check(trimmedContent)
        if localGuardResult.isBlocked {
            dlog("⛔ [editComment][LocalContentGuard] Blocked: \(localGuardResult.category.rawValue)")
            throw NSError(
                domain: "CommentService",
                code: -13,
                userInfo: [NSLocalizedDescriptionKey: localGuardResult.userMessage]
            )
        }

        // 🛡️ MODERATION: Re-run the full moderation pipeline on edited content.
        let signals = AuthenticitySignals(
            typedCharacters: trimmedContent.count,
            pastedCharacters: 0,
            typedVsPastedRatio: 1.0,
            largestPasteLength: 0,
            pasteEventCount: 0,
            typingDurationSeconds: 0,
            hasLargePaste: false
        )
        let moderationResult = try await ContentModerationService.moderateContent(
            text: trimmedContent,
            category: .comment,
            signals: signals
        )
        if moderationResult.shouldBlock {
            dlog("❌ [editComment] Blocked by moderation: \(moderationResult.reasons.joined(separator: ", "))")
            await MainActor.run {
                ModerationToastManager.shared.show(reasons: moderationResult.reasons)
            }
            throw NSError(
                domain: "CommentService",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Edited content flagged by moderation"]
            )
        }
        
        let commentRef = ref.child("postInteractions").child(postId).child("comments").child(commentId)
        
        // Verify ownership
        let snapshot = try await commentRef.getData()
        guard let commentData = snapshot.value as? [String: Any],
              let authorId = commentData["authorId"] as? String,
              authorId == userId else {
            throw NSError(domain: "CommentService", code: -4, userInfo: [NSLocalizedDescriptionKey: "You can only edit your own comments"])
        }
        
        // Update content and timestamp
        let updates: [String: Any] = [
            "content": trimmedContent,
            "updatedAt": Int64(Date().timeIntervalSince1970 * 1000),
            "isEdited": true
        ]
        
        try await commentRef.updateChildValues(updates)
        
        dlog("✅ Comment edited successfully")
        
        // Update local cache
        if var postComments = comments[postId] {
            if let index = postComments.firstIndex(where: { $0.id == commentId }) {
                var updatedComment = postComments[index]
                updatedComment.content = trimmedContent
                updatedComment.updatedAt = Date()
                postComments[index] = updatedComment
                comments[postId] = postComments
            }
        }
    }
    
    /// Delete comment
    func deleteComment(commentId: String, postId: String) async throws {
        dlog("🗑️ Deleting comment: \(commentId)")
        dlog("   Post ID: \(postId)")
        
        guard let userId = firebaseManager.currentUser?.uid else {
            dlog("❌ [DELETE] User not authenticated")
            throw NSError(domain: "CommentService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        dlog("   User ID: \(userId)")
        
        let commentRef = ref.child("postInteractions").child(postId).child("comments").child(commentId)
        dlog("   Path: postInteractions/\(postId)/comments/\(commentId)")
        
        // Verify ownership
        dlog("   Fetching comment data to verify ownership...")
        
        // ✅ FIX: Use observeSingleEvent instead of getData() for proper data retrieval
        let snapshot = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<DataSnapshot, Error>) in
            commentRef.observeSingleEvent(of: .value) { snapshot in
                continuation.resume(returning: snapshot)
            } withCancel: { error in
                continuation.resume(throwing: error)
            }
        }
        
        dlog("   Snapshot exists: \(snapshot.exists())")
        
        guard snapshot.exists() else {
            dlog("❌ [DELETE] Comment not found at path")
            throw NSError(domain: "CommentService", code: -6, userInfo: [NSLocalizedDescriptionKey: "Comment not found"])
        }
        
        guard let commentData = snapshot.value as? [String: Any] else {
            dlog("❌ [DELETE] Invalid comment data format")
            dlog("   Snapshot value type: \(type(of: snapshot.value))")
            dlog("   Snapshot value: \(String(describing: snapshot.value))")
            throw NSError(domain: "CommentService", code: -7, userInfo: [NSLocalizedDescriptionKey: "Invalid comment data"])
        }
        
        dlog("   Comment data keys: \(commentData.keys.joined(separator: ", "))")
        
        guard let authorId = commentData["authorId"] as? String else {
            dlog("❌ [DELETE] No authorId found in comment data")
            dlog("   Available keys: \(commentData.keys.joined(separator: ", "))")
            throw NSError(domain: "CommentService", code: -8, userInfo: [NSLocalizedDescriptionKey: "Comment has no author"])
        }
        
        dlog("   Author ID: \(authorId)")
        dlog("   Owner match: \(authorId == userId)")
        
        guard authorId == userId else {
            dlog("❌ [DELETE] User \(userId) is not owner \(authorId)")
            throw NSError(domain: "CommentService", code: -4, userInfo: [NSLocalizedDescriptionKey: "You can only delete your own comments"])
        }
        
        // P2-2 FIX: Check for replies directly in RTDB — never rely on the local cache,
        // which may be stale or not yet populated.
        let allCommentsSnapshot = try await ref
            .child("postInteractions").child(postId).child("comments")
            .getData()
        var replyCount = 0
        if allCommentsSnapshot.exists() {
            for child in allCommentsSnapshot.children.allObjects as? [DataSnapshot] ?? [] {
                if let data = child.value as? [String: Any],
                   let parentId = data["parentCommentId"] as? String,
                   parentId == commentId {
                    replyCount += 1
                }
            }
        }
        if replyCount > 0 {
            dlog("⚠️ [P2-2] Cannot delete comment with \(replyCount) replies (from DB)")
            throw NSError(domain: "CommentService", code: -5,
                         userInfo: [NSLocalizedDescriptionKey: "Cannot delete a comment that has replies. Delete the replies first."])
        }
        
        // Remove the comment
        try await commentRef.removeValue()
        
        // Decrement comment count on the post
        let countRef = ref.child("postInteractions").child(postId).child("commentCount")
        try await countRef.runTransactionBlock { currentData in
            if let currentCount = currentData.value as? Int {
                currentData.value = max(0, currentCount - 1)
            } else {
                currentData.value = 0
            }
            return TransactionResult.success(withValue: currentData)
        }
        
        dlog("✅ Comment deleted successfully")
        
        // Update local cache
        if var postComments = comments[postId] {
            postComments.removeAll { $0.id == commentId }
            comments[postId] = postComments
        }
        
        // Also remove from replies cache
        commentReplies.removeValue(forKey: commentId)
    }
    
    // MARK: - Interactions
    
    /// Toggle "Amen" (or lightbulb) on a comment
    /// - Parameters:
    ///   - commentId: The comment ID to toggle
    ///   - postId: The post ID (required for direct Firebase access)
    func toggleAmen(commentId: String, postId: String) async throws {
        dlog("🙏 Toggling Amen on comment: \(commentId) in post: \(postId)")
        
        guard let userId = firebaseManager.currentUser?.uid else {
            throw NSError(domain: "CommentService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // Reference to the comment's like status
        let commentRef = ref.child("postInteractions").child(postId).child("comments").child(commentId)
        let userLikeRef = commentRef.child("likedBy").child(userId)
        let likesCountRef = commentRef.child("likes")
        
        // Check current like status
        let snapshot = try await userLikeRef.getData()
        let hasLiked = snapshot.exists()
        
        // Toggle like status
        if hasLiked {
            // Remove like
            try await userLikeRef.removeValue()
            
            // Decrement count (use transaction for accuracy)
            try await likesCountRef.runTransactionBlock { currentData in
                if let currentCount = currentData.value as? Int {
                    currentData.value = max(0, currentCount - 1)
                } else {
                    currentData.value = 0
                }
                return TransactionResult.success(withValue: currentData)
            }
            
            dlog("✅ Removed amen from comment")
        } else {
            // Add like
            try await userLikeRef.setValue(true)
            
            // Increment count (use transaction for accuracy)
            try await likesCountRef.runTransactionBlock { currentData in
                if let currentCount = currentData.value as? Int {
                    currentData.value = currentCount + 1
                } else {
                    currentData.value = 1
                }
                return TransactionResult.success(withValue: currentData)
            }
            
            dlog("✅ Added amen to comment")
        }
        
        // Haptic feedback
        await MainActor.run {
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
        }
    }
    
    // MARK: - Real-time Listeners
    
    /// Start listening to comments for a post in Realtime Database
    func startListening(to postId: String) {
        // ✅ Prevent duplicate listeners
        if listenerPaths[postId] != nil {
            dlog("⚠️ Already listening to post: \(postId)")
            return
        }
        
        dlog("🔊 Starting real-time listener for comments on post: \(postId)")
        
        let commentsRef = ref.child("postInteractions").child(postId).child("comments")
        
        // ✅ CRITICAL FIX: Keep data synced locally even when app is offline
        // This ensures cached data persists across app restarts
        commentsRef.keepSynced(true)
        
        let handle = commentsRef.observe(.value) { [weak self] snapshot in
            guard let self = self else { return }

            // ⚠️ CRITICAL: Firebase DataSnapshot memory is only valid synchronously
            // within this callback. Extract everything into plain Swift value types
            // NOW, before dispatching to the main actor — never hold DataSnapshot
            // across an async boundary (causes heap corruption / SIGABRT).
            let snapshotExists = snapshot.exists()
            let childCount = snapshot.childrenCount

            // Pre-extract all child data synchronously on the Firebase background thread.
            struct RawComment {
                let key: String
                let data: [String: Any]
            }
            var rawComments: [RawComment] = []
            if snapshotExists {
                for child in snapshot.children.allObjects as? [DataSnapshot] ?? [] {
                    if let data = child.value as? [String: Any] {
                        rawComments.append(RawComment(key: child.key, data: data))
                    }
                }
            }
            // DataSnapshot is no longer referenced after this point.

            Task { @MainActor [weak self] in
                guard let self = self else { return }

                dlog("📥 [LISTENER] Real-time data received for post: \(postId)")
                dlog("   Snapshot exists: \(snapshotExists)")
                dlog("   Children count: \(childCount)")
                dlog("   Data source: \(rawComments.count) comment(s)")

                var fetchedComments: [Comment] = []
                var repliesMap: [String: [Comment]] = [:]

                for raw in rawComments {
                    let commentData = raw.data
                    guard let authorId = commentData["authorId"] as? String,
                          let authorName = commentData["authorName"] as? String,
                          let authorInitials = commentData["authorInitials"] as? String,
                          let content = commentData["content"] as? String,
                          let timestamp = commentData["timestamp"] as? Int64 else {
                        continue
                    }

                    // ✅ Get username and profile image from RTDB (stored during comment creation)
                    let authorUsername: String
                    if let storedUsername = commentData["authorUsername"] as? String, !storedUsername.isEmpty {
                        authorUsername = storedUsername
                        dlog("✅ Using stored username: @\(authorUsername)")
                    } else {
                        authorUsername = "user\(authorId.prefix(8))"
                        dlog("⚠️ No stored username, using fallback: @\(authorUsername)")
                    }

                    let authorProfileImageURL = commentData["authorProfileImageURL"] as? String
                    if let imageURL = authorProfileImageURL {
                        dlog("✅ Profile image URL found: \(imageURL)")
                    }

                    let comment = Comment(
                        id: raw.key,
                        postId: postId,
                        authorId: authorId,
                        authorName: authorName,
                        authorUsername: authorUsername,
                        authorInitials: authorInitials,
                        authorProfileImageURL: authorProfileImageURL,
                        content: content,
                        createdAt: Date(timeIntervalSince1970: Double(timestamp) / 1000.0),
                        updatedAt: Date(timeIntervalSince1970: Double(timestamp) / 1000.0),
                        amenCount: commentData["likes"] as? Int ?? 0,
                        replyCount: 0,
                        amenUserIds: [],
                        parentCommentId: commentData["parentCommentId"] as? String,
                        mentionedUserIds: nil
                    )

                    // P0-2 FIX: Check if this comment replaces an optimistic one.
                    // Match on clientRequestId written into RTDB, not content.hashValue —
                    // avoids false matches when two comments have identical content.
                    if let clientRequestId = commentData["clientRequestId"] as? String,
                       let tempId = self.optimisticComments[clientRequestId] {
                        dlog("🔄 [P0-2] Real comment \(raw.key) replaces optimistic \(tempId) via clientRequestId")
                        NotificationCenter.default.post(
                            name: Notification.Name("commentConfirmed"),
                            object: nil,
                            userInfo: [
                                "realId": raw.key,
                                "tempId": tempId,
                                "postId": postId
                            ]
                        )
                        self.optimisticComments.removeValue(forKey: clientRequestId)
                    }

                    fetchedComments.append(comment)
                }

                // Sort by timestamp
                fetchedComments.sort { $0.createdAt < $1.createdAt }

                // ✅ Separate top-level comments and replies
                let topLevelComments = fetchedComments.filter { $0.parentCommentId == nil }
                let replies = fetchedComments.filter { $0.parentCommentId != nil }

                // ✅ Guard: don't overwrite a populated cache with an empty snapshot.
                if topLevelComments.isEmpty, let existing = self.comments[postId], !existing.isEmpty {
                    dlog("⚠️ [LISTENER] Empty snapshot received — keeping \(existing.count) cached comment(s)")
                    return
                }

                // ✅ Build the full replies dict locally BEFORE touching any @Published property.
                // This prevents SwiftUI from rendering a half-updated state (comments updated but
                // commentReplies not yet updated) which causes LazyVStack cell recycling corruption → SIGABRT.
                for reply in replies {
                    guard let parentId = reply.parentCommentId else { continue }
                    if repliesMap[parentId] != nil {
                        repliesMap[parentId]?.append(reply)
                    } else {
                        repliesMap[parentId] = [reply]
                    }
                }
                for parentId in repliesMap.keys {
                    repliesMap[parentId]?.sort { $0.createdAt < $1.createdAt }
                }

                // ✅ Remove old reply parents that no longer exist in the new snapshot.
                let currentReplyParents = Set(replies.compactMap { $0.parentCommentId })
                let cachedReplyParents = Set(self.commentReplies.keys)
                var newCommentReplies = repliesMap
                for oldParent in cachedReplyParents where !currentReplyParents.contains(oldParent) {
                    newCommentReplies.removeValue(forKey: oldParent)
                }

                // ✅ Update commentReplies BEFORE comments so that when SwiftUI re-renders
                // due to the comments assignment, commentReplies already holds the correct
                // new data. Previously comments was set first, causing SwiftUI to compute
                // commentsWithReplies (which reads BOTH dicts) while commentReplies was still
                // being mutated — producing stale/nil ids → LazyVStack cell corruption → SIGABRT.
                self.commentReplies = newCommentReplies
                self.comments[postId] = topLevelComments

                dlog("✅ Real-time update: \(topLevelComments.count) comments, \(replies.count) replies")

                NotificationCenter.default.post(
                    name: Notification.Name("commentsUpdated"),
                    object: nil,
                    userInfo: ["postId": postId]
                )
            }
        }
        
        listenerPaths[postId] = handle
    }
    
    // P0-3 FIX: Stop listener for specific post (prevents memory leak).
    // Pass clearCache: true only when the post will not be shown again (e.g. full dismiss).
    // Leaving cache intact lets a screen that briefly disappears and returns avoid a re-fetch.
    func stopListening(to postId: String, clearCache: Bool = false) {
        guard let handle = listenerPaths[postId] else {
            dlog("⚠️ [P0-3] No listener to stop for post: \(postId)")
            return
        }
        
        ref.child("postInteractions").child(postId).child("comments")
            .removeObserver(withHandle: handle)
        
        listenerPaths.removeValue(forKey: postId)
        
        if clearCache {
            comments.removeValue(forKey: postId)
        }
        
        dlog("🔇 [P0-3] Stopped listener for post: \(postId), clearCache=\(clearCache) (active: \(listenerPaths.count))")
    }
    
    /// Stop all listeners
    func stopListening() {
        dlog("🔇 Stopping all comment listeners...")
        
        for (postId, handle) in listenerPaths {
            ref.child("postInteractions").child(postId).child("comments").removeObserver(withHandle: handle)
        }
        
        listenerPaths.removeAll()
        comments.removeAll()
        
        dlog("✅ All listeners stopped and cache cleared")
    }
    
    // MARK: - Helper Methods
    
    // P1-3: Timeout helper for network operations
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError(operation: "Comment submission timed out after \(seconds)s")
            }
            
            guard let result = try await group.next() else {
                throw TimeoutError(operation: "No result from task group")
            }
            group.cancelAll()
            return result
        }
    }
    
    /// Check if user has amened a comment
    /// - Parameters:
    ///   - commentId: The comment ID to check
    ///   - postId: The post ID (required since cache might not be populated yet)
    func hasUserAmened(commentId: String, postId: String) async -> Bool {
        guard let userId = firebaseManager.currentUser?.uid else { return false }
        
        let userLikeRef = ref.child("postInteractions").child(postId).child("comments").child(commentId).child("likedBy").child(userId)
        
        do {
            let snapshot = try await userLikeRef.getData()
            let hasLiked = snapshot.exists()
            dlog("✅ hasUserAmened check - commentId: \(commentId), postId: \(postId), result: \(hasLiked)")
            return hasLiked
        } catch {
            dlog("❌ Error checking amen status: \(error)")
            return false
        }
    }
    
    // MARK: - Notifications (for compatibility)
    
    private func createCommentNotification(
        postId: String,
        commentId: String,
        postAuthorId: String,
        commenterName: String
    ) async throws {
        guard let commenterId = firebaseManager.currentUser?.uid,
              commenterId != postAuthorId else { return }
        
        let db = Firestore.firestore()
        // Grouped comment notification — deterministic ID so multiple comments on same post
        // accumulate into a single notification row (Threads-style grouping)
        let deterministicId = "comment_group_\(postId)"
        let existingDoc = try? await db.collection("users").document(postAuthorId)
            .collection("notifications").document(deterministicId).getDocument()
        
        if let existing = existingDoc, existing.exists,
           var actors = existing.data()?["actorIds"] as? [String] {
            // Append actor if not already present, update count and preview
            if !actors.contains(commenterId) {
                actors.append(commenterId)
            }
            try? await db.collection("users").document(postAuthorId)
                .collection("notifications").document(deterministicId).updateData([
                    "actorIds": actors,
                    "actorCount": actors.count,
                    "fromUserId": commenterId,
                    "fromUserName": commenterName,
                    "commentId": commentId,
                    "isRead": false,
                    "updatedAt": FieldValue.serverTimestamp()
                ])
        } else {
            let notification: [String: Any] = [
                "toUserId": postAuthorId,
                "type": "comment",
                "fromUserId": commenterId,
                "fromUserName": commenterName,
                "postId": postId,
                "commentId": commentId,
                "actorIds": [commenterId],
                "actorCount": 1,
                "message": "\(commenterName) commented on your post",
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp(),
                "isRead": false
            ]
            try? await db.collection("users").document(postAuthorId)
                .collection("notifications").document(deterministicId).setData(notification)
        }
        dlog("📬 Comment notification sent to post author: \(postAuthorId)")
    }
    
    private func createReplyNotification(
        postId: String,
        commentId: String,
        replyId: String,
        parentAuthorId: String,
        replierName: String
    ) async throws {
        guard let replierId = firebaseManager.currentUser?.uid,
              replierId != parentAuthorId else { return }
        
        let db = Firestore.firestore()
        let notification: [String: Any] = [
            "toUserId": parentAuthorId,
            "type": "reply",
            "fromUserId": replierId,
            "fromUserName": replierName,
            "postId": postId,
            "commentId": commentId,
            "replyId": replyId,
            "message": "\(replierName) replied to your comment",
            "createdAt": FieldValue.serverTimestamp(),
            "isRead": false
        ]
        _ = try? await db.collection("users").document(parentAuthorId)
            .collection("notifications").addDocument(data: notification)
        dlog("📬 Reply notification sent to comment author: \(parentAuthorId)")
    }
    
    private func createMentionNotification(
        postId: String,
        commentId: String,
        mentionedUserId: String,
        mentionerName: String
    ) async throws {
        guard let mentionerId = firebaseManager.currentUser?.uid,
              mentionerId != mentionedUserId else { return }
        
        let db = Firestore.firestore()
        let notification: [String: Any] = [
            "toUserId": mentionedUserId,
            "type": "mention",
            "fromUserId": mentionerId,
            "fromUserName": mentionerName,
            "postId": postId,
            "commentId": commentId,
            "message": "\(mentionerName) mentioned you in a comment",
            "createdAt": FieldValue.serverTimestamp(),
            "isRead": false
        ]
        _ = try? await db.collection("users").document(mentionedUserId)
            .collection("notifications").addDocument(data: notification)
        dlog("📬 Mention notification sent to: \(mentionedUserId)")
    }
}
