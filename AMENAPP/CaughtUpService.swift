// CaughtUpService.swift
// AMENAPP
//
// Intelligent "You're All Caught Up" state machine with session-based tracking.
// Implements Instagram/Threads-style smart banner behavior that feels earned and intentional.
//
// Architecture:
//   • Session boundary: captures newest post at feed open
//   • Fresh content tracking: posts within the session boundary
//   • Visibility tracking: 70%+ visible for 0.8s+ to count as viewed
//   • Smart eligibility: requires all fresh posts viewed + scroll pause + low velocity
//   • Single-show per session with cooldowns
//   • Automatic invalidation when new posts arrive or feed refreshes

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - State Machine

enum CaughtUpBannerState: Equatable {
    case hidden       // Banner not shown, not tracking
    case tracking     // Session started, tracking fresh post consumption
    case eligible     // User has consumed fresh posts, eligible to show
    case visible      // Banner is currently shown
    case coolingDown  // Recently dismissed, in cooldown period
}

// MARK: - Session Boundary

struct FeedSessionBoundary {
    let sessionID: UUID
    let startedAt: Date
    let newestPostIDAtOpen: String?
    let newestPostTimestampAtOpen: Date?
}

// MARK: - Tuning Constants

enum CaughtUpBannerTuning {
    // Visibility thresholds for marking a post as "viewed"
    static let minVisibleRatioToCountViewed: CGFloat = 0.70
    static let minVisibleDurationToCountViewed: TimeInterval = 0.80

    // Last fresh post visibility requirements
    static let lastFreshVisibleRatio: CGFloat = 0.85
    static let lastFreshDwell: TimeInterval = 1.0

    // Timing
    static let eligibleDelay: TimeInterval = 0.9
    static let cooldownAfterDismiss: TimeInterval = 12.0
    static let autoDismissAfterVisible: TimeInterval = 5.0

    // Scroll behavior
    static let lowVelocityThreshold: CGFloat = 120
    static let fastScrollIgnoreThreshold: CGFloat = 1400

    // Minimum posts before banner can appear
    static let minimumPostsBeforeBanner = 6
}

// MARK: - Context

struct CaughtUpContext {
    var state: CaughtUpBannerState = .hidden

    var sessionBoundary: FeedSessionBoundary?

    var visiblePostIDs: Set<String> = []
    var viewedFreshPostIDs: Set<String> = []
    var freshPostIDsAtSessionStart: [String] = []

    var hasShownInSession: Bool = false
    var lastShownAt: Date?
    var lastDismissedAt: Date?

    var isRefreshing: Bool = false
    var isPaginating: Bool = false
    var hasNewPostsSinceSessionStart: Bool = false

    var scrollVelocity: CGFloat = 0
    var isUserNearFeedEnd: Bool = false
    var isUserActivelyDragging: Bool = false

    var eligibleSince: Date?
    var lastFreshPostFullyVisibleSince: Date?

    var totalFreshPostsCount: Int = 0
    var viewedFreshPostsCount: Int { viewedFreshPostIDs.count }
}

// MARK: - CaughtUpService

@MainActor
final class CaughtUpService: ObservableObject {
    static let shared = CaughtUpService()

    // MARK: Published

    /// Banner visibility state (for UI binding)
    @Published var isCaughtUp: Bool = false

    /// Triggers the rapid-refresh nudge ("Nothing new right now").
    @Published var showRapidRefreshNudge: Bool = false

    /// Triggers the deep-scroll pause reminder (120+ cards).
    @Published var showDeepScrollNudge: Bool = false

    // MARK: Private state

    /// Session-based context with state machine
    private var context = CaughtUpContext()

    /// In-memory set of seen post IDs this session (fast lookup, no Firestore read).
    private var seenIdsInMemory: Set<String> = []

    /// Posts visible to the user in the current 72-hour window (set by OpenTableView).
    private var currentWindowPostIds: Set<String> = []

    // Debounce: batch Firestore writes every 3 seconds.
    private var pendingWrites: [String: Date] = [:]
    private var writeTask: Task<Void, Never>?

    // Evaluation timer
    private var evaluationTimer: Timer?

    // Rapid-refresh detection
    private var refreshTimestamps: [Date] = []
    private let rapidRefreshWindow: TimeInterval = 60
    private let rapidRefreshThreshold: Int = 5

    // Deep-scroll detection
    private var cardsSeenThisSession: Int = 0
    private let deepScrollThreshold: Int = 120

    private lazy var db = Firestore.firestore()

    // MARK: Init

    private init() {
        startEvaluationTimer()
    }

    // MARK: - Public API: Session Management

    /// Start a new feed session with the current posts.
    /// Call this when the feed is first loaded or refreshed with new content.
    func startNewFeedSession(posts: [Post]) {
        context.sessionBoundary = FeedSessionBoundary(
            sessionID: UUID(),
            startedAt: Date(),
            newestPostIDAtOpen: posts.first?.firestoreId,
            newestPostTimestampAtOpen: posts.first?.createdAt
        )

        let freshPosts = posts.filter { post in
            guard let boundary = context.sessionBoundary else { return false }
            return post.createdAt <= (boundary.newestPostTimestampAtOpen ?? .distantPast)
        }

        context.freshPostIDsAtSessionStart = freshPosts.map(\.firestoreId)
        context.totalFreshPostsCount = freshPosts.count
        context.viewedFreshPostIDs.removeAll()
        context.visiblePostIDs.removeAll()

        context.state = .tracking
        context.hasShownInSession = false
        context.hasNewPostsSinceSessionStart = false
        context.eligibleSince = nil
        context.lastFreshPostFullyVisibleSince = nil

        isCaughtUp = false
    }

    /// Called when new posts are inserted (e.g., from pull-to-refresh or real-time updates).
    func onNewPostsInserted(_ newPosts: [Post]) {
        guard let boundary = context.sessionBoundary else { return }

        let newerThanBoundary = newPosts.contains {
            ($0.createdAt > (boundary.newestPostTimestampAtOpen ?? .distantPast))
        }

        if newerThanBoundary {
            context.hasNewPostsSinceSessionStart = true
            context.state = .hidden
            context.eligibleSince = nil
            context.lastFreshPostFullyVisibleSince = nil
            isCaughtUp = false
        }
    }

    /// Called when feed starts refreshing.
    func onRefreshStarted() {
        context.isRefreshing = true
        if context.state == .visible || context.state == .eligible {
            context.state = .hidden
            isCaughtUp = false
        }
    }

    /// Called when feed finishes refreshing with new posts.
    func onRefreshFinished(posts: [Post]) {
        context.isRefreshing = false
        startNewFeedSession(posts: posts)
    }

    /// Called when pagination starts.
    func onPaginationStarted() {
        context.isPaginating = true
    }

    /// Called when pagination finishes.
    func onPaginationFinished() {
        context.isPaginating = false
    }

    // MARK: - Public API: Scroll Tracking

    /// Update scroll velocity and dragging state.
    func onScroll(velocity: CGFloat, isDragging: Bool) {
        context.scrollVelocity = velocity
        context.isUserActivelyDragging = isDragging

        // Hide banner if user starts fast scrolling
        if context.state == .visible && abs(velocity) > CaughtUpBannerTuning.fastScrollIgnoreThreshold {
            dismissBanner()
        }
    }

    // MARK: - Public API: Post Visibility

    /// Called when a post's visibility changes (e.g., from GeometryReader).
    /// visibilityRatio: 0.0 to 1.0 indicating how much of the post is visible.
    /// dwellTime: how long the post has been at this visibility ratio.
    func onPostVisibilityChanged(postID: String, visibility: CGFloat, dwell: TimeInterval) {
        // Track which posts are currently visible
        if visibility >= CaughtUpBannerTuning.minVisibleRatioToCountViewed {
            context.visiblePostIDs.insert(postID)
        } else {
            context.visiblePostIDs.remove(postID)
        }

        // Mark as viewed if meets thresholds
        if visibility >= CaughtUpBannerTuning.minVisibleRatioToCountViewed &&
           dwell >= CaughtUpBannerTuning.minVisibleDurationToCountViewed &&
           context.freshPostIDsAtSessionStart.contains(postID) &&
           !context.viewedFreshPostIDs.contains(postID) {
            context.viewedFreshPostIDs.insert(postID)
            markSeen(postId: postID) // Legacy tracking
        }

        // Track last fresh post visibility
        updateLastFreshPostVisibility(postID: postID, visibility: visibility)

        // Update near-end status
        updateNearEndStatus(lastVisiblePostID: context.visiblePostIDs.max())
    }

    // MARK: - Legacy API (for backward compatibility)

    /// Called by OpenTableView when the post list updates.
    func setCurrentWindow(postIds: Set<String>) {
        currentWindowPostIds = postIds
    }

    /// Called when a post becomes visible for ≥1.5 seconds (legacy).
    func markSeen(postId: String) {
        guard !seenIdsInMemory.contains(postId) else { return }
        seenIdsInMemory.insert(postId)

        // Deep-scroll counter
        cardsSeenThisSession += 1
        if cardsSeenThisSession == deepScrollThreshold {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showDeepScrollNudge = true
            }
        }

        // Queue Firestore write (debounced)
        pendingWrites[postId] = Date()
        scheduleBatchWrite()
    }

    /// Call on every pull-to-refresh.
    @discardableResult
    func recordRefresh() -> Bool {
        let now = Date()
        refreshTimestamps.append(now)
        refreshTimestamps = refreshTimestamps.filter {
            now.timeIntervalSince($0) < rapidRefreshWindow
        }
        if refreshTimestamps.count >= rapidRefreshThreshold {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showRapidRefreshNudge = true
            }
            Task {
                try? await Task.sleep(for: .seconds(4))
                await MainActor.run {
                    withAnimation { showRapidRefreshNudge = false }
                }
            }
            return true
        }
        return false
    }

    /// Dismiss the deep-scroll nudge.
    func dismissDeepScrollNudge() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showDeepScrollNudge = false
        }
    }

    /// Called when the user taps "View older posts" — clears the caught-up state.
    func dismissCaughtUp() {
        dismissBanner()
    }

    /// Reset session counters on each new feed appearance.
    func resetSession() {
        cardsSeenThisSession = 0
        showDeepScrollNudge = false

        // Reset state machine
        resetCaughtUpStateForFeedMutation()

        // Reload seen IDs from Firestore
        Task { await loadSeenIdsFromFirestore() }
    }

    // MARK: - Private: State Machine Logic

    private func updateLastFreshPostVisibility(postID: String, visibility: CGFloat) {
        guard postID == context.freshPostIDsAtSessionStart.last else { return }

        if visibility >= CaughtUpBannerTuning.lastFreshVisibleRatio {
            if context.lastFreshPostFullyVisibleSince == nil {
                context.lastFreshPostFullyVisibleSince = Date()
            }
        } else {
            context.lastFreshPostFullyVisibleSince = nil
        }
    }

    private func updateNearEndStatus(lastVisiblePostID: String?) {
        guard let lastVisiblePostID else {
            context.isUserNearFeedEnd = false
            return
        }

        let freshIDs = context.freshPostIDsAtSessionStart
        guard let index = freshIDs.firstIndex(of: lastVisiblePostID) else {
            context.isUserNearFeedEnd = false
            return
        }

        let remaining = freshIDs.count - 1 - index
        context.isUserNearFeedEnd = remaining <= 1
    }

    private func evaluateEligibility() {
        guard context.state == .tracking || context.state == .hidden else { return }
        guard !context.hasShownInSession else { return }
        guard !context.isRefreshing else { return }
        guard !context.isPaginating else { return }
        guard !context.hasNewPostsSinceSessionStart else { return }

        let minimumViewedThreshold = min(max(CaughtUpBannerTuning.minimumPostsBeforeBanner, context.totalFreshPostsCount), 10)

        let consumedAllFreshPosts =
            Set(context.freshPostIDsAtSessionStart).isSubset(of: context.viewedFreshPostIDs)

        let viewedEnoughPosts = context.viewedFreshPostsCount >= minimumViewedThreshold || consumedAllFreshPosts

        guard viewedEnoughPosts else { return }
        guard context.isUserNearFeedEnd else { return }

        context.eligibleSince = context.eligibleSince ?? Date()
        context.state = .eligible
    }

    private func maybeRevealBanner(now: Date = Date()) {
        guard context.state == .eligible else { return }
        guard !context.hasShownInSession else { return }
        guard !context.isRefreshing else { return }
        guard !context.isPaginating else { return }
        guard !context.hasNewPostsSinceSessionStart else { return }
        guard !context.isUserActivelyDragging else { return }
        guard abs(context.scrollVelocity) < CaughtUpBannerTuning.lowVelocityThreshold else { return }
        guard canShowAfterCooldown(now: now) else { return }

        guard let eligibleSince = context.eligibleSince,
              now.timeIntervalSince(eligibleSince) >= CaughtUpBannerTuning.eligibleDelay else { return }

        guard let lastFreshVisibleSince = context.lastFreshPostFullyVisibleSince,
              now.timeIntervalSince(lastFreshVisibleSince) >= CaughtUpBannerTuning.lastFreshDwell else { return }

        showBanner()
    }

    private func showBanner() {
        context.state = .visible
        context.hasShownInSession = true
        context.lastShownAt = Date()

        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            isCaughtUp = true
        }

        // Auto-dismiss after duration
        Task {
            try? await Task.sleep(for: .seconds(CaughtUpBannerTuning.autoDismissAfterVisible))
            await MainActor.run {
                if context.state == .visible {
                    dismissBanner()
                }
            }
        }
    }

    private func dismissBanner() {
        context.state = .coolingDown
        context.lastDismissedAt = Date()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isCaughtUp = false
        }
    }

    private func evaluateCooldown(now: Date = Date()) {
        guard context.state == .coolingDown else { return }

        if let lastDismissedAt = context.lastDismissedAt,
           now.timeIntervalSince(lastDismissedAt) > CaughtUpBannerTuning.cooldownAfterDismiss {
            context.state = .hidden
        }
    }

    private func canShowAfterCooldown(now: Date = Date()) -> Bool {
        guard let lastDismissedAt = context.lastDismissedAt else { return true }
        return now.timeIntervalSince(lastDismissedAt) >= CaughtUpBannerTuning.cooldownAfterDismiss
    }

    private func resetCaughtUpStateForFeedMutation() {
        context.state = .hidden
        context.eligibleSince = nil
        context.lastFreshPostFullyVisibleSince = nil
        context.hasShownInSession = false
        context.viewedFreshPostIDs.removeAll()
        context.visiblePostIDs.removeAll()

        isCaughtUp = false
    }

    private func startEvaluationTimer() {
        evaluationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let now = Date()
                self.evaluateEligibility()
                self.maybeRevealBanner(now: now)
                self.evaluateCooldown(now: now)
            }
        }
    }

    // MARK: - Firestore: seed seen IDs

    private func loadSeenIdsFromFirestore() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let cutoff = Date().addingTimeInterval(-72 * 3600)
        do {
            let snapshot = try await db
                .collection("users").document(uid)
                .collection("seenPosts")
                .whereField("seenAt", isGreaterThan: Timestamp(date: cutoff))
                .getDocuments()
            let ids = Set(snapshot.documents.map { $0.documentID })
            await MainActor.run {
                seenIdsInMemory.formUnion(ids)
            }
        } catch {
            // Non-critical: in-memory set still works without Firestore data
        }
    }

    // MARK: - Firestore: batch write seen posts

    private func scheduleBatchWrite() {
        writeTask?.cancel()
        writeTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await flushPendingWrites()
        }
    }

    private func flushPendingWrites() async {
        guard let uid = Auth.auth().currentUser?.uid,
              !pendingWrites.isEmpty else { return }

        let toWrite = pendingWrites
        pendingWrites = [:]

        let batch = db.batch()
        let seenRef = db.collection("users").document(uid).collection("seenPosts")

        for (postId, seenAt) in toWrite {
            let docRef = seenRef.document(postId)
            batch.setData(["postId": postId, "seenAt": Timestamp(date: seenAt)], forDocument: docRef)
        }

        do {
            try await batch.commit()
        } catch {
            for (id, date) in toWrite where pendingWrites[id] == nil {
                pendingWrites[id] = date
            }
        }
    }
}
