//
//  ActivityFeedService.swift
//  AMENAPP
//
//  Created by Assistant on 1/24/26.
//
//  Service for managing global and community activity feeds
//  Uses Realtime Database for instant updates
//

import Foundation
import Combine
import FirebaseDatabase
import FirebaseAuth

// MARK: - Activity Types

enum ActivityType: String, Codable {
    case postCreated = "post_created"
    case postLiked = "post_liked"
    case postAmened = "post_amened"
    case commented = "commented"
    case reposted = "reposted"
    case followedUser = "followed_user"
    case prayingStarted = "praying_started"
}

// MARK: - Activity Model

struct Activity: Identifiable, Codable {
    let id: String
    let type: ActivityType
    let userId: String
    let userName: String
    let userInitials: String
    let timestamp: Int64
    
    // Optional fields depending on activity type
    var postId: String?
    var postContent: String?
    var targetUserId: String?
    var targetUserName: String?
    var communityId: String?
    
    var date: Date {
        Date(timeIntervalSince1970: Double(timestamp) / 1000.0)
    }
    
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    var displayText: String {
        switch type {
        case .postCreated:
            return "\(userName) shared a post"
        case .postLiked:
            return "\(userName) lit a lightbulb"
        case .postAmened:
            return "\(userName) said Amen"
        case .commented:
            return "\(userName) commented"
        case .reposted:
            return "\(userName) reposted"
        case .followedUser:
            if let targetName = targetUserName {
                return "\(userName) followed \(targetName)"
            }
            return "\(userName) followed someone"
        case .prayingStarted:
            return "\(userName) is praying"
        }
    }
    
    var icon: String {
        switch type {
        case .postCreated:
            return "square.and.pencil"
        case .postLiked:
            return "lightbulb.fill"
        case .postAmened:
            return "hands.clap.fill"
        case .commented:
            return "bubble.left.fill"
        case .reposted:
            return "arrow.2.squarepath"
        case .followedUser:
            return "person.badge.plus.fill"
        case .prayingStarted:
            return "hands.sparkles.fill"
        }
    }
    
    var iconColor: String {
        switch type {
        case .postCreated:
            return "blue"
        case .postLiked:
            return "orange"
        case .postAmened:
            return "black"
        case .commented:
            return "green"
        case .reposted:
            return "purple"
        case .followedUser:
            return "pink"
        case .prayingStarted:
            return "blue"
        }
    }
}

// MARK: - Activity Feed Service

@MainActor
class ActivityFeedService: ObservableObject {
    static let shared = ActivityFeedService()
    
    @Published var globalActivities: [Activity] = []
    @Published var communityActivities: [String: [Activity]] = [:] // communityId -> activities
    @Published var isLoading = false
    @Published var globalFeedError: String?
    
    // Lazy to avoid accessing Database.database() before AppDelegate sets isPersistenceEnabled.
    private lazy var database: Database = Database.database()
    private var ref: DatabaseReference {
        database.reference()
    }

    // Cached root DatabaseReference so deinit (nonisolated) can safely remove observers
    // without crossing the MainActor boundary.
    nonisolated(unsafe) private var _rootRef: DatabaseReference?

    nonisolated(unsafe) private var globalObserverHandle: DatabaseHandle?
    nonisolated(unsafe) private var communityObserverHandles: [String: DatabaseHandle] = [:]

    // O(1) dedup sets — avoids O(n) `contains(where:)` on every childAdded event
    private var globalSeenIds: Set<String> = []
    private var communitySeenIds: [String: Set<String>] = [:]

    private init() {}

    deinit {
        // Remove all Realtime DB handles synchronously.
        // Firebase DatabaseReference.removeObserver(withHandle:) is thread-safe.
        // Use _rootRef (nonisolated) so we don't touch the @MainActor-isolated `database`.
        guard let dbRef = _rootRef else { return }
        if let handle = globalObserverHandle {
            dbRef.child("activityFeed/global").removeObserver(withHandle: handle)
        }
        for (communityId, handle) in communityObserverHandles {
            dbRef.child("communityActivity/\(communityId)").removeObserver(withHandle: handle)
        }
    }
    
    var currentUserId: String {
        Auth.auth().currentUser?.uid ?? "anonymous"
    }
    
    var currentUserName: String {
        Auth.auth().currentUser?.displayName ?? "User"
    }
    
    var currentUserInitials: String {
        let name = currentUserName
        let components = name.components(separatedBy: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        }
        return name.prefix(2).uppercased()
    }
    
    // MARK: - Log Activities
    
    /// Log a post created activity
    func logPostCreated(postId: String, postContent: String, communityId: String? = nil) {
        let activity: [String: Any] = [
            "type": ActivityType.postCreated.rawValue,
            "userId": currentUserId,
            "userName": currentUserName,
            "userInitials": currentUserInitials,
            "timestamp": ServerValue.timestamp(),
            "postId": postId,
            "postContent": postContent.prefix(100) // First 100 chars
        ]
        
        logToGlobalFeed(activity: activity)
        
        if let communityId = communityId {
            logToCommunityFeed(communityId: communityId, activity: activity)
        }
    }
    
    /// Log a lightbulb/like activity
    func logLightbulb(postId: String, postContent: String, communityId: String? = nil) {
        let activity: [String: Any] = [
            "type": ActivityType.postLiked.rawValue,
            "userId": currentUserId,
            "userName": currentUserName,
            "userInitials": currentUserInitials,
            "timestamp": ServerValue.timestamp(),
            "postId": postId,
            "postContent": postContent.prefix(100)
        ]
        
        logToGlobalFeed(activity: activity)
        
        if let communityId = communityId {
            logToCommunityFeed(communityId: communityId, activity: activity)
        }
    }
    
    /// Log an amen activity
    func logAmen(postId: String, postContent: String, communityId: String? = nil) {
        let activity: [String: Any] = [
            "type": ActivityType.postAmened.rawValue,
            "userId": currentUserId,
            "userName": currentUserName,
            "userInitials": currentUserInitials,
            "timestamp": ServerValue.timestamp(),
            "postId": postId,
            "postContent": postContent.prefix(100)
        ]
        
        logToGlobalFeed(activity: activity)
        
        if let communityId = communityId {
            logToCommunityFeed(communityId: communityId, activity: activity)
        }
    }
    
    /// Log a comment activity
    func logComment(postId: String, postContent: String, communityId: String? = nil) {
        let activity: [String: Any] = [
            "type": ActivityType.commented.rawValue,
            "userId": currentUserId,
            "userName": currentUserName,
            "userInitials": currentUserInitials,
            "timestamp": ServerValue.timestamp(),
            "postId": postId,
            "postContent": postContent.prefix(100)
        ]
        
        logToGlobalFeed(activity: activity)
        
        if let communityId = communityId {
            logToCommunityFeed(communityId: communityId, activity: activity)
        }
    }
    
    /// Log a repost activity
    func logRepost(postId: String, postContent: String, communityId: String? = nil) {
        let activity: [String: Any] = [
            "type": ActivityType.reposted.rawValue,
            "userId": currentUserId,
            "userName": currentUserName,
            "userInitials": currentUserInitials,
            "timestamp": ServerValue.timestamp(),
            "postId": postId,
            "postContent": postContent.prefix(100)
        ]
        
        logToGlobalFeed(activity: activity)
        
        if let communityId = communityId {
            logToCommunityFeed(communityId: communityId, activity: activity)
        }
    }
    
    /// Log a follow activity
    func logFollow(targetUserId: String, targetUserName: String) {
        let activity: [String: Any] = [
            "type": ActivityType.followedUser.rawValue,
            "userId": currentUserId,
            "userName": currentUserName,
            "userInitials": currentUserInitials,
            "timestamp": ServerValue.timestamp(),
            "targetUserId": targetUserId,
            "targetUserName": targetUserName
        ]
        
        logToGlobalFeed(activity: activity)
    }
    
    /// Log praying started activity
    func logPrayingStarted(postId: String, communityId: String? = nil) {
        let activity: [String: Any] = [
            "type": ActivityType.prayingStarted.rawValue,
            "userId": currentUserId,
            "userName": currentUserName,
            "userInitials": currentUserInitials,
            "timestamp": ServerValue.timestamp(),
            "postId": postId
        ]
        
        logToGlobalFeed(activity: activity)
        
        if let communityId = communityId {
            logToCommunityFeed(communityId: communityId, activity: activity)
        }
    }
    
    // MARK: - Private Logging Methods
    
    private func logToGlobalFeed(activity: [String: Any]) {
        let activityRef = ref.child("activityFeed/global").childByAutoId()
        activityRef.setValue(activity) { error, _ in
            if let error = error {
                print("❌ Failed to log global activity: \(error)")
            } else {
                print("✅ Global activity logged")
            }
        }
    }
    
    private func logToCommunityFeed(communityId: String, activity: [String: Any]) {
        let activityRef = ref.child("communityActivity/\(communityId)").childByAutoId()
        activityRef.setValue(activity) { error, _ in
            if let error = error {
                print("❌ Failed to log community activity: \(error)")
            } else {
                print("✅ Community activity logged")
            }
        }
    }
    
    // MARK: - Observe Activities
    
    /// Start observing global activity feed
    func startObservingGlobalFeed() {
        guard globalObserverHandle == nil else { return }

        print("🔊 Starting global activity feed observer")
        globalFeedError = nil

        // Cache root ref now (on MainActor) so deinit can use it safely.
        if _rootRef == nil { _rootRef = ref }

        let query = ref.child("activityFeed/global")
            .queryOrdered(byChild: "timestamp")
            .queryLimited(toLast: 50)

        globalObserverHandle = query.observe(
            .childAdded,
            with: { [weak self] snapshot in
                self?.globalFeedError = nil
                self?.processActivitySnapshot(snapshot, isGlobal: true)
            },
            withCancel: { [weak self] error in
                print("❌ Global activity feed error: \(error)")
                DispatchQueue.main.async {
                    self?.globalFeedError = error.localizedDescription
                }
            }
        )
    }
    
    /// Start observing community activity feed
    func startObservingCommunityFeed(communityId: String) {
        guard communityObserverHandles[communityId] == nil else { return }
        
        // Ensure _rootRef is set so deinit can clean up community handles
        // even if startObservingGlobalFeed was never called
        if _rootRef == nil { _rootRef = ref }
        
        print("🔊 Starting community activity feed observer for: \(communityId)")
        
        let query = ref.child("communityActivity/\(communityId)")
            .queryOrdered(byChild: "timestamp")
            .queryLimited(toLast: 50)
        
        let handle = query.observe(.childAdded) { [weak self] snapshot in
            self?.processActivitySnapshot(snapshot, communityId: communityId)
        }
        
        communityObserverHandles[communityId] = handle
    }
    
    private func processActivitySnapshot(_ snapshot: DataSnapshot, isGlobal: Bool = false, communityId: String? = nil) {
        guard let data = snapshot.value as? [String: Any],
              let typeString = data["type"] as? String,
              let type = ActivityType(rawValue: typeString),
              let userId = data["userId"] as? String,
              let userName = data["userName"] as? String,
              let userInitials = data["userInitials"] as? String,
              let timestamp = data["timestamp"] as? Int64 else {
            print("⚠️ Invalid activity data")
            return
        }
        
        let activity = Activity(
            id: snapshot.key,
            type: type,
            userId: userId,
            userName: userName,
            userInitials: userInitials,
            timestamp: timestamp,
            postId: data["postId"] as? String,
            postContent: data["postContent"] as? String,
            targetUserId: data["targetUserId"] as? String,
            targetUserName: data["targetUserName"] as? String,
            communityId: data["communityId"] as? String
        )
        
        Task { @MainActor in
            if isGlobal {
                // O(1) set-based dedup
                guard !globalSeenIds.contains(activity.id) else { return }
                globalSeenIds.insert(activity.id)
                globalActivities.insert(activity, at: 0)
                if globalActivities.count > 50 {
                    let removed = globalActivities.removeLast()
                    globalSeenIds.remove(removed.id)
                }
            } else if let communityId = communityId {
                var seenIds = communitySeenIds[communityId] ?? []
                guard !seenIds.contains(activity.id) else { return }
                seenIds.insert(activity.id)
                communitySeenIds[communityId] = seenIds

                var activities = communityActivities[communityId] ?? []
                activities.insert(activity, at: 0)
                if activities.count > 50 {
                    let removed = activities.removeLast()
                    communitySeenIds[communityId]?.remove(removed.id)
                }
                communityActivities[communityId] = activities
            }
        }
    }
    
    // MARK: - Stop Observing
    
    /// Stop observing global feed
    func stopObservingGlobalFeed() {
        if let handle = globalObserverHandle {
            ref.child("activityFeed/global").removeObserver(withHandle: handle)
            globalObserverHandle = nil
            globalSeenIds.removeAll()
            print("🔇 Stopped global activity feed observer")
        }
    }

    /// Tear down and restart the global feed observer — used for pull-to-retry.
    func retryGlobalFeed() {
        stopObservingGlobalFeed()
        globalActivities.removeAll()
        startObservingGlobalFeed()
    }

    /// Stop observing community feed
    func stopObservingCommunityFeed(communityId: String) {
        if let handle = communityObserverHandles[communityId] {
            ref.child("communityActivity/\(communityId)").removeObserver(withHandle: handle)
            communityObserverHandles.removeValue(forKey: communityId)
            communitySeenIds.removeValue(forKey: communityId)
            dlog("🔇 Stopped community activity feed observer for: \(communityId)")
        }
    }

    /// Stop all observers
    func stopAllObservers() {
        stopObservingGlobalFeed()
        // P0 FIX: Snapshot keys before iterating — stopObservingCommunityFeed mutates
        // the dictionary via removeValue(forKey:), which causes undefined behaviour if
        // we iterate over .keys while it is being modified.
        let communityIds = Array(communityObserverHandles.keys)
        for communityId in communityIds {
            stopObservingCommunityFeed(communityId: communityId)
        }
    }
    
    // MARK: - Fetch Activities (one-time)
    
    /// Fetch global activities once
    func fetchGlobalActivities() async throws -> [Activity] {
        dlog("📥 Fetching global activities...")
        
        let query = ref.child("activityFeed/global")
            .queryOrdered(byChild: "timestamp")
            .queryLimited(toLast: 50)
        
        let snapshot = try await query.getData()
        var activities: [Activity] = []
        
        for childSnapshot in snapshot.children.allObjects as? [DataSnapshot] ?? [] {
            if let data = childSnapshot.value as? [String: Any],
               let typeString = data["type"] as? String,
               let type = ActivityType(rawValue: typeString),
               let userId = data["userId"] as? String,
               let userName = data["userName"] as? String,
               let userInitials = data["userInitials"] as? String,
               let timestamp = data["timestamp"] as? Int64 {
                
                let activity = Activity(
                    id: childSnapshot.key,
                    type: type,
                    userId: userId,
                    userName: userName,
                    userInitials: userInitials,
                    timestamp: timestamp,
                    postId: data["postId"] as? String,
                    postContent: data["postContent"] as? String,
                    targetUserId: data["targetUserId"] as? String,
                    targetUserName: data["targetUserName"] as? String,
                    communityId: data["communityId"] as? String
                )
                
                activities.append(activity)
            }
        }
        
        // Sort by timestamp (newest first)
        activities.sort { $0.timestamp > $1.timestamp }
        
        print("✅ Fetched \(activities.count) global activities")
        return activities
    }
    
    /// Fetch community activities once
    func fetchCommunityActivities(communityId: String) async throws -> [Activity] {
        print("📥 Fetching community activities for: \(communityId)")
        
        let query = ref.child("communityActivity/\(communityId)")
            .queryOrdered(byChild: "timestamp")
            .queryLimited(toLast: 50)
        
        let snapshot = try await query.getData()
        var activities: [Activity] = []
        
        for childSnapshot in snapshot.children.allObjects as? [DataSnapshot] ?? [] {
            if let data = childSnapshot.value as? [String: Any],
               let typeString = data["type"] as? String,
               let type = ActivityType(rawValue: typeString),
               let userId = data["userId"] as? String,
               let userName = data["userName"] as? String,
               let userInitials = data["userInitials"] as? String,
               let timestamp = data["timestamp"] as? Int64 {
                
                let activity = Activity(
                    id: childSnapshot.key,
                    type: type,
                    userId: userId,
                    userName: userName,
                    userInitials: userInitials,
                    timestamp: timestamp,
                    postId: data["postId"] as? String,
                    postContent: data["postContent"] as? String,
                    targetUserId: data["targetUserId"] as? String,
                    targetUserName: data["targetUserName"] as? String,
                    communityId: data["communityId"] as? String
                )
                
                activities.append(activity)
            }
        }
        
        // Sort by timestamp (newest first)
        activities.sort { $0.timestamp > $1.timestamp }
        
        print("✅ Fetched \(activities.count) community activities")
        return activities
    }
}
