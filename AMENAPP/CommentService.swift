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
    // _db is nonisolated(unsafe) so deinit can access it without a main-actor hop.
    nonisolated(unsafe) private var _db: Database?
    private var database: Database {
        if let db = _db { return db }
        let db = Database.database()
        _db = db
        return db
    }
    private var ref: DatabaseReference {
        database.reference()
    }
    nonisolated(unsafe) private var listenerPaths: [String: DatabaseHandle] = [:]
    // Cached root ref for safe use in nonisolated deinit
    nonisolated(unsafe) private var _rootRef: DatabaseReference?
    
    // P0-1 FIX: Prevent duplicate comment creation
    private var inFlightCommentRequests: Set<String> = []
    
    // P0-2 FIX: Track optimistic comments for replacement.
    // Key: clientRequestId (written into RTDB alongside the comment).
    // Value: the local tempId used for UI dedup.
    // Using clientRequestId instead of content.hashValue avoids false matches
    // when two comments have identical content.
    private var optimisticComments: [String: String] = [:]  // clientRequestId -> tempId

    // ── Comment quality gate state ─────────────────────────────────────────
    // When checkCommentQuality returns "nudge", we store the pending submission
    // here so the UI can resume it after the user dismisses the nudge sheet.
    struct PendingCommentSubmission {
        let postId: String
        let content: String
        let clientCommentId: String
        let mentionedUserIds: [String]?
        let post: Post?
        let nudges: [String]
        let safetyDecision: CommentQualityResponse.SafetyDecision
    }
    @Published var pendingNudge: PendingCommentSubmission?

    /// Error thrown when the server quality check returns "nudge".
    /// The caller (PostDetailView) catches this and presents the nudge sheet.
    struct CommentNudgeRequired: Error {
        let pending: PendingCommentSubmission
    }

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
        // ✅ FIX CR-14: Don't call Firebase methods from deinit - causes crashes
        // Listeners should be cleaned up explicitly via stopListening() before deallocation
        // This safety check just logs if cleanup was missed
        #if DEBUG
        if !listenerPaths.isEmpty {
            print("⚠️ [CommentService] Deallocating with \(listenerPaths.count) active listeners. Call stopListening() before release.")
        }
        #endif
        
        // Note: Can't clear @MainActor-isolated dictionaries from deinit (not async)
        // Memory will be released automatically when the object deallocates
        // Explicit cleanup should happen via stopListening() before deallocation
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
        
        // Check comment permissions (legacy field — kept for backward compat)
        let permissions = post.commentPermissions ?? .everyone
        switch permissions {
        case .everyone:
            break  // fall through to replyPermission check
        case .following:
            guard await FollowService.shared.isFollowing(userId: post.authorId) else { return false }
        case .mentioned:
            guard let profile = try? await userService.fetchUserProfile(userId: currentUserId),
                  !profile.username.isEmpty else { return false }
            let mentions = extractMentions(from: post.content)
            guard mentions.contains(where: { $0.lowercased() == "@\(profile.username.lowercased())" }) else {
                return false
            }
        case .off:
            return false
        }

        // Check reply permission (Feature 1 — finer-grained than commentPermissions)
        let replyPerm = post.replyPermission ?? .everyone
        switch replyPerm {
        case .everyone:
            return true

        case .followers:
            // Current user must be followed by the author, OR must follow the author.
            // Interpretation: "followers" = people who follow the post author.
            return await FollowService.shared.isFollowing(userId: post.authorId)

        case .mutuals:
            // Both users must follow each other (mutual follow).
            let state = await FollowStateManager.shared.getState(for: post.authorId)
            return state == .mutualFollow

        case .mentioned:
            guard let profile = try? await userService.fetchUserProfile(userId: currentUserId),
                  !profile.username.isEmpty else { return false }
            let mentions = extractMentions(from: post.content)
            return mentions.contains { $0.lowercased() == "@\(profile.username.lowercased())" }
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
            lazy var db = Firestore.firestore()
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

        // ── SERVER QUALITY + SAFETY GATE ─────────────────────────────────────
        // Call checkCommentQuality BEFORE writing to the database.
        // The server stores a decision record keyed on uid+clientRequestId.
        // addComment (CF) will reject writes that lack a valid decision record.
        //
        // fail-closed: .serverError → do not publish.
        dlog("🛡️ [CommentGateway] Checking quality for comment on post: \(postId)")
        let gatewayOutcome = await CommentQualityGateway.shared.check(
            text: content,
            postId: postId,
            clientCommentId: clientRequestId
        )
        switch gatewayOutcome {
        case .serverError(let message):
            optimisticComments.removeValue(forKey: clientRequestId)
            dlog("❌ [CommentGateway] Server error: \(message)")
            throw NSError(
                domain: "CommentService",
                code: -20,
                userInfo: [NSLocalizedDescriptionKey: message]
            )

        case .decided(let response):
            switch response.decision {
            case .block:
                optimisticComments.removeValue(forKey: clientRequestId)
                dlog("⛔ [CommentGateway] BLOCKED by safety check")
                throw NSError(
                    domain: "CommentService",
                    code: -21,
                    userInfo: [NSLocalizedDescriptionKey: "This comment was blocked by our safety system. Please review and revise before posting."]
                )

            case .nudge:
                // Surface nudges to the UI. Throw CommentNudgeRequired so
                // PostDetailView can show the nudge sheet. If the user chooses
                // "post anyway", they call resumeAfterNudge(_:) which skips this check.
                optimisticComments.removeValue(forKey: clientRequestId)
                dlog("💡 [CommentGateway] Nudge required: \(response.nudges.count) suggestion(s)")
                let pending = PendingCommentSubmission(
                    postId: postId,
                    content: content,
                    clientCommentId: clientRequestId,
                    mentionedUserIds: mentionedUserIds,
                    post: post,
                    nudges: response.nudges,
                    safetyDecision: response.safetyDecision
                )
                pendingNudge = pending
                throw CommentNudgeRequired(pending: pending)

            case .publish:
                dlog("✅ [CommentGateway] Quality check passed — proceeding to write")
                // Continue to write path below
            }
        }
        // ── END GATE ────────────────────────────────────────────────────────

        // Re-add clientRequestId to optimisticComments (was removed on nudge/error)
        // For the publish path, it was never removed so this is a no-op.
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
                userInfo: ["tempId": tempId, "postId": postId, "error": lastError as Any]
            )
            
            throw lastError ?? NSError(domain: "CommentService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Comment submission failed after all retries"])
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

            // P0-C FIX: async let with inline closures ({}()) triggers swift_task_dealloc crash
            // when the parent Task is cancelled mid-flight. Use withTaskGroup so child tasks
            // are always properly scoped and cancelled before the parent exits.
            enum ModerationResult {
                case moderation(ModerationDecision)
                case safety(CommentSafetySystem.SafetyCheckResult?)
                case aiDetection(AIContentDetectionResult)
            }

            var moderationResult: ModerationDecision?
            var safetyResult: CommentSafetySystem.SafetyCheckResult?
            var aiDetectionResult: AIContentDetectionResult?

            await withTaskGroup(of: ModerationResult?.self) { group in
                group.addTask {
                    guard let result = try? await ContentModerationService.moderateContent(
                        text: capturedContent,
                        category: .comment,
                        signals: signals
                    ) else { return nil }
                    return .moderation(result)
                }
                group.addTask {
                    // SECURITY FIX (MEDIUM 2026-06-11): Use do/catch instead of try? so
                    // a network failure or CF error does not silently bypass the safety check.
                    // On error return a blocking safety result to fail closed.
                    do {
                        let result = try await CommentSafetySystem.shared.checkCommentSafety(
                            content: capturedContent,
                            postId: capturedPostId,
                            postAuthorId: capturedPostAuthorId,
                            commenterId: capturedUserId
                        )
                        return .safety(result)
                    } catch {
                        dlog("[CommentService] Safety check failed — failing closed: \(error)")
                        let blockedResult = CommentSafetySystem.SafetyCheckResult(
                            action: .blockAndReview,
                            violations: [],
                            confidence: 1.0,
                            userMessage: nil,
                            suggestedRevisions: nil,
                            cooldownSeconds: nil,
                            requiresRevision: false
                        )
                        return .safety(blockedResult)
                    }
                }
                group.addTask {
                    let result = await AIContentDetectionService.shared.detectAIContent(capturedContent)
                    return .aiDetection(result)
                }
                for await result in group {
                    switch result {
                    case .moderation(let r):   moderationResult = r
                    case .safety(let r):       safetyResult = r
                    case .aiDetection(let r):  aiDetectionResult = r
                    case nil: break
                    }
                }
            }

            guard let moderationResult, let aiDetectionResult else {
                return
            }

            // Snapshot the safety result as a let constant so the MainActor.run closure
            // doesn't capture a mutable var (which triggers a Swift 6 warning).
            let snapshotSafetyResult = safetyResult

            // Read @MainActor-isolated properties on the main actor.
            let (moderationShouldBlock, moderationReasons, safetyIsBlocking, isAIGenerated) =
                await MainActor.run {
                    (
                        moderationResult.shouldBlock,
                        moderationResult.reasons,
                        snapshotSafetyResult?.action.isBlocking == true,
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

    // MARK: - Resume after nudge (user chose "Post anyway")

    /// Called when the user acknowledges the nudge sheet and chooses to post anyway.
    /// The decision record already exists on the server (written by checkCommentQuality),
    /// so we call the write path directly using the original clientCommentId.
    ///
    /// Returns the posted Comment (same contract as addComment).
    func resumeAfterNudge(_ pending: PendingCommentSubmission) async throws -> Comment {
        pendingNudge = nil
        dlog("➡️ [CommentGateway] User chose to post anyway after nudge")

        guard let userId = firebaseManager.currentUser?.uid else {
            throw NSError(domain: "CommentService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }

        // Fetch user profile for author metadata
        let userProfile: UserModel? = try? await userService.fetchUserProfile(userId: userId)
        let authorUsername: String
        let authorProfileImageURL: String?
        if let profile = userProfile {
            authorUsername = profile.username
            authorProfileImageURL = profile.profileImageURL
        } else {
            authorUsername = "user\(userId.prefix(8))"
            authorProfileImageURL = nil
        }

        // Haptic
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()

        // Re-register the clientRequestId in the optimistic map
        let tempId = UUID().uuidString
        optimisticComments[pending.clientCommentId] = tempId

        // Write directly — skips the quality gate (record already exists)
        let interactionsService = PostInteractionsService.shared
        var commentId: String?
        var retryCount = 0
        let maxRetries = 3
        var lastError: Error?

        while retryCount < maxRetries {
            do {
                commentId = try await withTimeout(seconds: 10) {
                    try await interactionsService.addComment(
                        postId: pending.postId,
                        content: pending.content,
                        authorInitials: self.firebaseManager.currentUser?.displayName?
                            .prefix(2).uppercased() ?? "??",
                        authorUsername: authorUsername,
                        authorProfileImageURL: authorProfileImageURL,
                        clientRequestId: pending.clientCommentId
                    )
                }
                break
            } catch {
                lastError = error
                retryCount += 1
                if retryCount < maxRetries {
                    try await Task.sleep(nanoseconds: UInt64(Double(retryCount) * 1_000_000_000))
                }
            }
        }

        guard let finalCommentId = commentId else {
            optimisticComments.removeValue(forKey: pending.clientCommentId)
            throw lastError ?? NSError(domain: "CommentService", code: -1,
                                       userInfo: [NSLocalizedDescriptionKey: "Comment submission failed"])
        }

        optimisticComments.removeValue(forKey: pending.clientCommentId)
        await NewAccountRestrictionService.shared.recordAction(.comment, userId: userId)

        dlog("✅ [resumeAfterNudge] Comment written: \(finalCommentId)")

        return Comment(
            id: finalCommentId,
            postId: pending.postId,
            authorId: userId,
            authorName: firebaseManager.currentUser?.displayName ?? "Unknown User",
            authorUsername: authorUsername,
            authorInitials: firebaseManager.currentUser?.displayName?.prefix(2).uppercased() ?? "??",
            authorProfileImageURL: authorProfileImageURL,
            content: pending.content,
            createdAt: Date(),
            updatedAt: Date(),
            amenCount: 0,
            replyCount: 0,
            amenUserIds: [],
            parentCommentId: nil,
            mentionedUserIds: pending.mentionedUserIds
        )
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
    
    /// Fetch all comments by a specific user across all posts.
    /// Requires a Firestore composite index on collectionGroup "comments":
    ///   userId ASC, createdAt DESC
    func fetchUserComments(userId: String, limit: Int = 50) async throws -> [Comment] {
        dlog("📥 Fetching comments for user: \(userId)")
        
        lazy var db = Firestore.firestore()
        let snap = try await db
            .collectionGroup("comments")
            .whereField("userId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()

        let fetched: [Comment] = snap.documents.compactMap { doc in
            try? doc.data(as: Comment.self)
        }
        dlog("✅ Fetched \(fetched.count) comments for user: \(userId)")
        return fetched
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
        
        // ✅ FIX CR-5: Use transaction to atomically check replies and delete
        // This prevents race condition where reply is added between check and delete
        let commentsRef = ref.child("postInteractions").child(postId).child("comments")
        
        try await commentsRef.runTransactionBlock { currentData in
            guard let commentsDict = currentData.value as? [String: Any] else {
                // No comments exist, nothing to delete
                return TransactionResult.abort()
            }
            
            // Check if any comment has this as parent
            var replyCount = 0
            for (_, commentData) in commentsDict {
                if let data = commentData as? [String: Any],
                   let parentId = data["parentCommentId"] as? String,
                   parentId == commentId {
                    replyCount += 1
                }
            }
            
            if replyCount > 0 {
                dlog("⚠️ [CR-5] Cannot delete comment with \(replyCount) replies")
                return TransactionResult.abort()
            }
            
            // No replies found - safe to delete
            var updatedComments = commentsDict
            updatedComments.removeValue(forKey: commentId)
            currentData.value = updatedComments
            return TransactionResult.success(withValue: currentData)
        }
        
        dlog("✅ Comment deleted atomically (no replies)")
        
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
    /// - Parameter currentlyAmened: The UI's known state BEFORE the tap. Pass this to avoid
    ///   a `getData()` round-trip that can return stale offline-cached values.
    func toggleAmen(commentId: String, postId: String, currentlyAmened: Bool) async throws {
        dlog("🙏 Toggling Amen on comment: \(commentId) in post: \(postId)")
        
        guard let userId = firebaseManager.currentUser?.uid else {
            throw NSError(domain: "CommentService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // Reference to the comment's like status
        let commentRef = ref.child("postInteractions").child(postId).child("comments").child(commentId)

        // ✅ FIX CR-10: Use single transaction to atomically update both likedBy and count
        // This prevents race condition where two simultaneous likes can cause desync
        try await commentRef.runTransactionBlock { currentData in
            guard var commentDict = currentData.value as? [String: Any] else {
                return TransactionResult.abort()
            }
            
            var likedByDict = commentDict["likedBy"] as? [String: Any] ?? [:]
            var currentCount = commentDict["likes"] as? Int ?? 0
            
            if currentlyAmened {
                // Remove like
                likedByDict.removeValue(forKey: userId)
                currentCount = max(0, currentCount - 1)
            } else {
                // Add like
                likedByDict[userId] = true
                currentCount += 1
            }
            
            commentDict["likedBy"] = likedByDict
            commentDict["likes"] = currentCount
            currentData.value = commentDict
            
            return TransactionResult.success(withValue: currentData)
        }
        
        dlog("✅ Toggled amen atomically (liked: \(!currentlyAmened))")
        
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

        // Cache root ref for safe use in nonisolated deinit
        let currentRef = ref
        if _rootRef == nil { _rootRef = currentRef }

        let commentsRef = currentRef.child("postInteractions").child(postId).child("comments")
        
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
                    
                    // ✅ FIX CR-6: Filter out blocked users
                    if BlockService.shared.blockedUsers.contains(authorId) {
                        continue
                    }

                    // ✅ Get username and profile image from RTDB (stored during comment creation)
                    let authorUsername: String
                    if let storedUsername = commentData["authorUsername"] as? String, !storedUsername.isEmpty {
                        authorUsername = storedUsername
                    } else {
                        authorUsername = "user\(authorId.prefix(8))"
                    }

                    let authorProfileImageURL = commentData["authorProfileImageURL"] as? String

                    // Extract which users have amened this comment from likedBy dict.
                    // This lets PostCommentRow initialize hasAmened locally without
                    // an async RTDB getData() call that can return stale cached results.
                    let amenUserIds: [String]
                    if let likedBy = commentData["likedBy"] as? [String: Any] {
                        amenUserIds = Array(likedBy.keys)
                    } else {
                        amenUserIds = []
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
                        amenUserIds: amenUserIds,
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

                // Guard: only ignore a transient empty snapshot when the node *exists* but
                // returned no parseable children (can happen if RTDB sends a partial frame
                // before the real data arrives on first attach). If the node doesn't exist
                // (snapshotExists == false) the user deleted the last comment — let it through
                // so the comment list correctly clears.
                if topLevelComments.isEmpty && snapshotExists,
                   let existing = self.comments[postId], !existing.isEmpty {
                    dlog("⚠️ [LISTENER] Empty snapshot received (node exists) — keeping \(existing.count) cached comment(s)")
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
        commentReplies.removeAll()  // P1 FIX: Clear reply cache to prevent stale data leaking to next session
        
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
        
        lazy var db = Firestore.firestore()
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
            do {
                try await db.collection("users").document(postAuthorId)
                    .collection("notifications").document(deterministicId).updateData([
                        "actorIds": actors,
                        "actorCount": actors.count,
                        "fromUserId": commenterId,
                        "fromUserName": commenterName,
                        "commentId": commentId,
                        "isRead": false,
                        "updatedAt": FieldValue.serverTimestamp()
                    ])
                dlog("📬 Comment notification updated for post author: \(postAuthorId)")
            } catch {
                dlog("⚠️ Comment notification update failed for post \(postId): \(error.localizedDescription)")
            }
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
            do {
                try await db.collection("users").document(postAuthorId)
                    .collection("notifications").document(deterministicId).setData(notification)
                dlog("📬 Comment notification created for post author: \(postAuthorId)")
            } catch {
                dlog("⚠️ Comment notification failed for post \(postId): \(error.localizedDescription)")
            }
        }
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
        
        lazy var db = Firestore.firestore()
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
        do {
            try await db.collection("users").document(parentAuthorId)
                .collection("notifications").addDocument(data: notification)
            dlog("📬 Reply notification sent to comment author: \(parentAuthorId)")
        } catch {
            dlog("⚠️ CommentService: failed to send reply notification to \(parentAuthorId) — \(error.localizedDescription)")
        }
    }
    
    private func createMentionNotification(
        postId: String,
        commentId: String,
        mentionedUserId: String,
        mentionerName: String
    ) async throws {
        guard let mentionerId = firebaseManager.currentUser?.uid,
              mentionerId != mentionedUserId else { return }
        
        lazy var db = Firestore.firestore()
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
        do {
            try await db.collection("users").document(mentionedUserId)
                .collection("notifications").addDocument(data: notification)
            dlog("📬 Mention notification sent to: \(mentionedUserId)")
        } catch {
            dlog("⚠️ CommentService: failed to send mention notification to \(mentionedUserId) — \(error.localizedDescription)")
        }
    }
}
