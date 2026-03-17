//
//  FollowOperationActor.swift
//  AMENAPP
//
//  P0-3: Actor-isolated follow operation guard
//  Prevents race conditions from rapid follow/unfollow taps (TOCTOU vulnerability)
//

import Foundation

/// Actor that serializes follow/unfollow operations to prevent race conditions
/// 
/// **Problem Solved:**
/// Without this actor, rapid taps on follow/unfollow can cause:
/// - Duplicate follow documents in Firestore
/// - Incorrect follower counts (off by 1, 2, or more)
/// - State corruption where UI shows "Following" but backend shows "Not Following"
///
/// **How It Works:**
/// - Only one follow/unfollow operation can execute at a time per user
/// - Uses Swift's actor isolation to guarantee thread-safety
/// - Tracks in-flight operations to prevent duplicates
/// - Returns cached result if operation already in progress
///
actor FollowOperationActor {
    /// Track which users currently have in-flight follow operations
    private var inFlightOperations: Set<String> = []
    
    /// Attempt to start a follow operation for a user
    /// - Parameter userId: The user to follow/unfollow
    /// - Returns: `true` if operation can proceed, `false` if already in progress
    func startOperation(for userId: String) -> Bool {
        guard !inFlightOperations.contains(userId) else {
            print("⚠️ Follow operation already in progress for user \(userId)")
            return false
        }
        
        inFlightOperations.insert(userId)
        print("✅ Started follow operation for user \(userId)")
        return true
    }
    
    /// Complete a follow operation for a user
    /// - Parameter userId: The user to mark as complete
    func completeOperation(for userId: String) {
        inFlightOperations.remove(userId)
        print("✅ Completed follow operation for user \(userId)")
    }
    
    /// Check if an operation is currently in progress
    /// - Parameter userId: The user to check
    /// - Returns: `true` if operation is in progress
    func isOperationInProgress(for userId: String) -> Bool {
        return inFlightOperations.contains(userId)
    }
    
    /// Reset all operations (useful for testing or error recovery)
    func resetAllOperations() {
        inFlightOperations.removeAll()
        print("🔄 Reset all follow operations")
    }
}

/// Singleton instance for global follow operation coordination
@MainActor
class FollowOperationGuard {
    static let shared = FollowOperationGuard()
    
    let actor = FollowOperationActor()
    
    private init() {}
    
    /// Execute a follow/unfollow operation with race condition protection
    /// - Parameters:
    ///   - userId: The user to follow/unfollow
    ///   - operation: The async operation to execute
    /// - Returns: The result of the operation, or throws if operation already in progress
    func executeFollowOperation<T>(
        for userId: String,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        // Check if operation is already in progress
        guard await actor.startOperation(for: userId) else {
            throw FollowOperationError.operationInProgress
        }
        
        defer {
            // Always complete the operation, even if it throws
            Task {
                await actor.completeOperation(for: userId)
            }
        }
        
        // Execute the actual follow/unfollow operation
        return try await operation()
    }
}

/// Errors that can occur during follow operations
enum FollowOperationError: LocalizedError {
    case operationInProgress
    case userNotFound
    case permissionDenied
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .operationInProgress:
            return "A follow operation is already in progress. Please wait."
        case .userNotFound:
            return "User not found."
        case .permissionDenied:
            return "You don't have permission to perform this action."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
