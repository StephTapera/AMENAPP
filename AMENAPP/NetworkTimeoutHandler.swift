//
//  NetworkTimeoutHandler.swift
//  AMENAPP
//
//  P1-5 FIX: Timeout handling for network requests
//

import Foundation

enum TimeoutError: Error {
    case timeout(message: String)
    
    var localizedDescription: String {
        switch self {
        case .timeout(let message):
            return message
        }
    }
}

extension Task where Failure == Error {
    /// Adds a timeout to an async task
    /// - Parameters:
    ///   - seconds: Timeout duration in seconds
    ///   - timeoutMessage: Custom message for timeout error
    ///   - operation: The async operation to execute
    /// - Returns: Result of the task or throws TimeoutError
    static func withTimeout(
        seconds: TimeInterval = 10,
        timeoutMessage: String = "Request timed out. Please check your connection and try again.",
        operation: @escaping @Sendable () async throws -> Success
    ) async throws -> Success {
        try await withThrowingTaskGroup(of: Success.self) { group in
            // Add the actual operation
            group.addTask {
                try await operation()
            }
            
            // Add timeout task
            group.addTask {
                try await Task<Never, Never>.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError.timeout(message: timeoutMessage)
            }
            
            // Return first completed task (either result or timeout)
            guard let result = try await group.next() else {
                throw TimeoutError.timeout(message: timeoutMessage)
            }
            
            // Cancel remaining tasks
            group.cancelAll()
            
            return result
        }
    }
}

// MARK: - Usage Examples

/*
 // Example 1: Fetch user data with timeout
 let userData = try await Task.withTimeout(seconds: 10) {
     try await fetchUserData(userId: userId)
 }
 
 // Example 2: Upload image with custom timeout
 let imageURL = try await Task.withTimeout(
     seconds: 30,
     timeoutMessage: "Image upload is taking longer than expected. Please try again."
 ) {
     try await uploadImage(imageData)
 }
 
 // Example 3: Load comments with timeout
 try await Task.withTimeout(seconds: 10) {
     await loadComments()
 }
 
 // Example 4: Handle timeout gracefully
 do {
     let result = try await Task.withTimeout(seconds: 5) {
         try await someNetworkCall()
     }
 } catch let error as TimeoutError {
     dlog("⏱️ Timeout: \(error.localizedDescription)")
     // Show user-friendly error
 } catch {
     dlog("❌ Error: \(error)")
 }
 */
