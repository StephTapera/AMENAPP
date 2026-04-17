//
//  ActionThreadService.swift
//  AMENAPP
//
//  Core service for Action Thread CRUD, state transitions, and participant management.
//  All sensitive state transitions are audited. Feature-flagged via AMENFeatureFlags.
//
//  Firestore paths:
//    posts/{postId}/actionThreads/{threadId}
//    posts/{postId}/actionThreads/{threadId}/steps/{stepId}
//    posts/{postId}/actionThreads/{threadId}/participants/{userId}
//    posts/{postId}/actionThreads/{threadId}/audit/{entryId}
//    users/{userId}/actionThreadMemberships/{threadId}
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class ActionThreadService: ObservableObject {
    
    static let shared = ActionThreadService()
    
    @Published private(set) var activeThreads: [String: ActionThread] = [:]  // threadId → thread
    @Published private(set) var isLoading = false
    
    private let db = Firestore.firestore()
    private var listeners: [String: ListenerRegistration] = [:]
    
    // In-flight guards
    private var createInFlight: Set<String> = []  // postId dedup
    private var transitionInFlight: Set<String> = []  // threadId dedup
    
    private init() {}
    
    deinit {
        listeners.values.forEach { $0.remove() }
    }
    
    // MARK: - Feature Guard
    
    private var isEnabled: Bool {
        AMENFeatureFlags.shared.actionThreadsEnabled
    }
    
    // MARK: - Create Thread
    
    /// Create a new Action Thread attached to a post. Returns the thread ID.
    /// Requires the caller to be the post author or have sufficient trust.
    func createThread(
        postId: String,
        type: ActionThreadType,
        visibility: ActionThreadVisibility = .participants,
        sensitivityLevel: CareSensitivityLevel = .standard,
        title: String? = nil,
        description: String? = nil,
        intent: SupportIntent? = nil,
        initialSteps: [ActionStep] = []
    ) async throws -> String {
        guard isEnabled else { throw ActionThreadError.featureDisabled }
        guard let userId = Auth.auth().currentUser?.uid else { throw ActionThreadError.notAuthenticated }
        guard !createInFlight.contains(postId) else { throw ActionThreadError.operationInFlight }
        createInFlight.insert(postId)
        defer { createInFlight.remove(postId) }
        
        // Verify the post exists and get the author
        let postDoc = try await db.collection("posts").document(postId).getDocument()
        guard let postData = postDoc.data(),
              let postAuthorId = postData["authorId"] as? String else {
            throw ActionThreadError.postNotFound
        }
        
        // Permission check: only post author or invited coordinators can create threads
        guard postAuthorId == userId else {
            throw ActionThreadError.permissionDenied("Only the post author can create action threads")
        }
        
        // Trust constraint check
        let eligible = await ActionThreadPermissionsService.shared.checkEligibility(
            userId: userId,
            constraint: .createActionThread
        )
        guard eligible.isEligible else {
            throw ActionThreadError.trustRequirementNotMet(eligible.reason)
        }
        
        let threadId = UUID().uuidString
        let now = Date()
        
        let thread = ActionThread(
            id: threadId,
            postId: postId,
            postAuthorId: postAuthorId,
            creatorUserId: userId,
            type: type,
            visibility: visibility,
            state: .active,
            sensitivityLevel: sensitivityLevel,
            title: title,
            description: description,
            intent: intent,
            createdAt: now,
            updatedAt: now,
            completedAt: nil,
            expiresAt: Calendar.current.date(byAdding: .day, value: 30, to: now),
            participantCount: 1,
            completedStepCount: 0,
            totalStepCount: initialSteps.count
        )
        
        let batch = db.batch()
        
        // Write thread document
        let threadRef = db.collection("posts").document(postId)
            .collection("actionThreads").document(threadId)
        try batch.setData(from: thread, forDocument: threadRef)
        
        // Write owner as first participant
        let ownerParticipant = ActionThreadParticipant(
            id: userId,
            userId: userId,
            displayName: Auth.auth().currentUser?.displayName ?? "",
            username: nil,
            profileImageURL: Auth.auth().currentUser?.photoURL?.absoluteString,
            role: .owner,
            joinedAt: now,
            lastActiveAt: now,
            status: .active
        )
        let participantRef = threadRef.collection("participants").document(userId)
        try batch.setData(from: ownerParticipant, forDocument: participantRef)
        
        // Write initial steps
        for (index, var step) in initialSteps.enumerated() {
            step.sortOrder = index
            let stepRef = threadRef.collection("steps").document(step.id)
            try batch.setData(from: step, forDocument: stepRef)
        }
        
        // Write audit entry
        let auditEntry = ActionThreadAuditEntry(
            id: UUID().uuidString,
            threadId: threadId,
            actorUserId: userId,
            action: .threadCreated,
            detail: "Created \(type.displayName) thread",
            timestamp: now,
            metadata: ["visibility": visibility.rawValue]
        )
        let auditRef = threadRef.collection("audit").document(auditEntry.id)
        try batch.setData(from: auditEntry, forDocument: auditRef)
        
        // Denormalize to post document for fast feed filtering
        let postRef = db.collection("posts").document(postId)
        batch.updateData([
            "actionThreadId": threadId,
            "actionThreadType": type.rawValue,
            "hasActiveActionThread": true
        ], forDocument: postRef)
        
        // Write membership reference for the user
        let membershipRef = db.collection("users").document(userId)
            .collection("actionThreadMemberships").document(threadId)
        batch.setData([
            "threadId": threadId,
            "postId": postId,
            "type": type.rawValue,
            "role": "owner",
            "joinedAt": Timestamp(date: now),
            "state": "active"
        ], forDocument: membershipRef)
        
        try await batch.commit()
        
        activeThreads[threadId] = thread
        
        // Record trust event
        if AMENFeatureFlags.shared.trustSignalsEnabled {
            Task.detached {
                await TrustEventRecorder.shared.record(TrustEvent(
                    id: UUID().uuidString,
                    userId: userId,
                    eventType: .actionStepCompleted,
                    category: .care,
                    value: 0.3,
                    source: "ActionThreadService",
                    relatedEntityId: threadId,
                    timestamp: now,
                    metadata: ["threadType": type.rawValue]
                ))
            }
        }
        
        return threadId
    }
    
    // MARK: - Transition State
    
    /// Transition a thread to a new state. Only valid transitions are allowed.
    func transitionState(
        postId: String,
        threadId: String,
        to newState: ActionThreadState
    ) async throws {
        guard isEnabled else { return }
        guard let userId = Auth.auth().currentUser?.uid else { throw ActionThreadError.notAuthenticated }
        guard !transitionInFlight.contains(threadId) else { return }
        transitionInFlight.insert(threadId)
        defer { transitionInFlight.remove(threadId) }
        
        let threadRef = db.collection("posts").document(postId)
            .collection("actionThreads").document(threadId)
        let doc = try await threadRef.getDocument()
        guard let thread = try? doc.data(as: ActionThread.self) else {
            throw ActionThreadError.threadNotFound
        }
        
        // Validate transition
        guard isValidTransition(from: thread.state, to: newState) else {
            throw ActionThreadError.invalidStateTransition(thread.state.rawValue, newState.rawValue)
        }
        
        // Permission check
        guard thread.creatorUserId == userId || thread.postAuthorId == userId else {
            throw ActionThreadError.permissionDenied("Only thread owner can change state")
        }
        
        let now = Date()
        var updates: [String: Any] = [
            "state": newState.rawValue,
            "updatedAt": Timestamp(date: now)
        ]
        if newState == .completed {
            updates["completedAt"] = Timestamp(date: now)
        }
        
        try await threadRef.updateData(updates)
        
        // Update denormalized post field
        if newState == .completed || newState == .archived || newState == .expired {
            try await db.collection("posts").document(postId).updateData([
                "hasActiveActionThread": false
            ])
        }
        
        // Audit
        let auditEntry = ActionThreadAuditEntry(
            id: UUID().uuidString,
            threadId: threadId,
            actorUserId: userId,
            action: newState == .completed ? .threadCompleted :
                    newState == .paused ? .threadPaused :
                    newState == .archived ? .threadArchived : .threadActivated,
            detail: "State changed to \(newState.rawValue)",
            timestamp: now,
            metadata: nil
        )
        try await threadRef.collection("audit").document(auditEntry.id)
            .setData(from: auditEntry)
        
        // Update local cache
        if var cached = activeThreads[threadId] {
            cached.state = newState
            cached.updatedAt = now
            activeThreads[threadId] = cached
        }
    }
    
    // MARK: - Complete Step
    
    /// Mark a step as completed within a thread.
    func completeStep(
        postId: String,
        threadId: String,
        stepId: String
    ) async throws {
        guard isEnabled else { return }
        guard let userId = Auth.auth().currentUser?.uid else { throw ActionThreadError.notAuthenticated }
        
        let stepRef = db.collection("posts").document(postId)
            .collection("actionThreads").document(threadId)
            .collection("steps").document(stepId)
        
        let now = Date()
        try await stepRef.updateData([
            "state": ActionStepState.completed.rawValue,
            "completedAt": Timestamp(date: now),
            "completedBy": userId,
            "updatedAt": Timestamp(date: now)
        ])
        
        // Increment completed step count on thread
        let threadRef = db.collection("posts").document(postId)
            .collection("actionThreads").document(threadId)
        try await threadRef.updateData([
            "completedStepCount": FieldValue.increment(Int64(1)),
            "updatedAt": Timestamp(date: now)
        ])
        
        // Audit
        let auditEntry = ActionThreadAuditEntry(
            id: UUID().uuidString,
            threadId: threadId,
            actorUserId: userId,
            action: .stepCompleted,
            detail: "Completed step \(stepId)",
            timestamp: now,
            metadata: nil
        )
        try await threadRef.collection("audit").document(auditEntry.id)
            .setData(from: auditEntry)
        
        // Record trust event for care follow-through
        if AMENFeatureFlags.shared.proofOfCareEnabled {
            Task.detached {
                await TrustEventRecorder.shared.record(TrustEvent(
                    id: UUID().uuidString,
                    userId: userId,
                    eventType: .actionStepCompleted,
                    category: .care,
                    value: 0.5,
                    source: "ActionThreadService",
                    relatedEntityId: threadId,
                    timestamp: now,
                    metadata: ["stepId": stepId]
                ))
            }
        }
    }
    
    // MARK: - Add Participant
    
    /// Invite a user to participate in a thread. Requires owner/coordinator permission.
    /// Never auto-adds users — always creates an invite that must be accepted.
    func inviteParticipant(
        postId: String,
        threadId: String,
        inviteeUserId: String,
        inviteeDisplayName: String,
        role: ActionThreadParticipant.ParticipantRole = .supporter
    ) async throws {
        guard isEnabled else { return }
        guard let userId = Auth.auth().currentUser?.uid else { throw ActionThreadError.notAuthenticated }
        
        // Check blocked status
        let isBlocked = ModerationService.shared.isBlocked(userId: inviteeUserId)
        guard !isBlocked else { throw ActionThreadError.userBlocked }
        
        // Check inviter permissions
        let permissions = await ActionThreadPermissionsService.shared.getPermissions(
            userId: userId, threadId: threadId, postId: postId
        )
        guard permissions.canAddParticipants else {
            throw ActionThreadError.permissionDenied("You cannot add participants to this thread")
        }
        
        let now = Date()
        let participant = ActionThreadParticipant(
            id: inviteeUserId,
            userId: inviteeUserId,
            displayName: inviteeDisplayName,
            username: nil,
            profileImageURL: nil,
            role: role,
            joinedAt: now,
            lastActiveAt: nil,
            status: .invited  // Always invited, never auto-added
        )
        
        let threadRef = db.collection("posts").document(postId)
            .collection("actionThreads").document(threadId)
        
        try await threadRef.collection("participants").document(inviteeUserId)
            .setData(from: participant)
        
        // Audit
        let auditEntry = ActionThreadAuditEntry(
            id: UUID().uuidString,
            threadId: threadId,
            actorUserId: userId,
            action: .participantAdded,
            detail: "Invited \(inviteeDisplayName)",
            timestamp: now,
            metadata: ["inviteeId": inviteeUserId, "role": role.rawValue]
        )
        try await threadRef.collection("audit").document(auditEntry.id)
            .setData(from: auditEntry)
        
        // Send notification to invitee
        if AMENFeatureFlags.shared.actionThreadsEnabled {
            Task.detached {
                await ActionThreadNotificationService.shared.sendInviteNotification(
                    threadId: threadId,
                    postId: postId,
                    inviteeUserId: inviteeUserId,
                    inviterName: Auth.auth().currentUser?.displayName ?? "Someone"
                )
            }
        }
    }
    
    // MARK: - Observe Threads for Post
    
    /// Start observing action threads for a specific post.
    func observeThreads(forPostId postId: String) {
        guard isEnabled else { return }
        let key = "post_\(postId)"
        guard listeners[key] == nil else { return }
        
        let query = db.collection("posts").document(postId)
            .collection("actionThreads")
            .whereField("state", in: ["active", "paused", "suggested"])
        
        listeners[key] = query.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self, let docs = snapshot?.documents else { return }
            Task { @MainActor in
                for doc in docs {
                    if let thread = try? doc.data(as: ActionThread.self) {
                        self.activeThreads[thread.id] = thread
                    }
                }
            }
        }
    }
    
    /// Stop observing threads for a post.
    func stopObservingThreads(forPostId postId: String) {
        let key = "post_\(postId)"
        listeners[key]?.remove()
        listeners.removeValue(forKey: key)
    }
    
    // MARK: - Fetch User's Thread Memberships
    
    /// Fetch all action threads the current user is a member of.
    func fetchMyThreadMemberships() async throws -> [(threadId: String, postId: String, type: String, role: String)] {
        guard isEnabled else { return [] }
        guard let userId = Auth.auth().currentUser?.uid else { return [] }
        
        let snapshot = try await db.collection("users").document(userId)
            .collection("actionThreadMemberships")
            .whereField("state", isEqualTo: "active")
            .order(by: "joinedAt", descending: true)
            .limit(to: 50)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            let data = doc.data()
            guard let threadId = data["threadId"] as? String,
                  let postId = data["postId"] as? String,
                  let type = data["type"] as? String,
                  let role = data["role"] as? String else { return nil }
            return (threadId, postId, type, role)
        }
    }
    
    // MARK: - Validation
    
    private func isValidTransition(from: ActionThreadState, to: ActionThreadState) -> Bool {
        switch (from, to) {
        case (.suggested, .active), (.suggested, .archived):    return true
        case (.draft, .active), (.draft, .archived):            return true
        case (.active, .paused), (.active, .completed), (.active, .archived): return true
        case (.paused, .active), (.paused, .archived):          return true
        default: return false
        }
    }
}

// MARK: - Error Types

enum ActionThreadError: LocalizedError {
    case featureDisabled
    case notAuthenticated
    case operationInFlight
    case postNotFound
    case threadNotFound
    case permissionDenied(String)
    case trustRequirementNotMet(String)
    case invalidStateTransition(String, String)
    case userBlocked
    
    var errorDescription: String? {
        switch self {
        case .featureDisabled: return "Action threads are not available"
        case .notAuthenticated: return "You must be signed in"
        case .operationInFlight: return "Operation already in progress"
        case .postNotFound: return "Post not found"
        case .threadNotFound: return "Thread not found"
        case .permissionDenied(let reason): return reason
        case .trustRequirementNotMet(let reason): return reason
        case .invalidStateTransition(let from, let to): return "Cannot transition from \(from) to \(to)"
        case .userBlocked: return "Cannot interact with this user"
        }
    }
}
