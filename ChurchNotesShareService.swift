//
//  ChurchNotesShareService.swift
//  AMENAPP
//
//  Client-side service for calling Church Notes sharing Cloud Functions
//

import Foundation
import FirebaseFunctions

@MainActor
class ChurchNotesShareService: ObservableObject {
    static let shared = ChurchNotesShareService()
    
    @Published var isProcessing = false
    @Published var lastError: Error?
    
    private let functions = Functions.functions()
    
    private init() {}
    
    // MARK: - Share Note with Users
    
    /// Share a church note with specific users (server-side validation)
    func shareNote(_ note: ChurchNote, withUserIds userIds: [String]) async throws -> ShareResult {
        guard let noteId = note.id else {
            throw ShareError.invalidNote
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        let callable = functions.httpsCallable("shareChurchNote")
        
        let data: [String: Any] = [
            "noteId": noteId,
            "recipientUserIds": userIds
        ]
        
        do {
            let result = try await callable.call(data)
            
            guard let resultData = result.data as? [String: Any],
                  let success = resultData["success"] as? Bool,
                  let sharedWithCount = resultData["sharedWithCount"] as? Int,
                  let sharedWith = resultData["sharedWith"] as? [String] else {
                throw ShareError.invalidResponse
            }
            
            print("✅ Note shared with \(sharedWithCount) users")
            
            return ShareResult(
                success: success,
                sharedWithCount: sharedWithCount,
                sharedWith: sharedWith
            )
        } catch let error as NSError {
            print("❌ Share note error: \(error)")
            
            if error.domain == FunctionsErrorDomain {
                let code = FunctionsErrorCode(rawValue: error.code)
                
                switch code {
                case .unauthenticated:
                    throw ShareError.notAuthenticated
                case .permissionDenied:
                    throw ShareError.permissionDenied
                case .notFound:
                    throw ShareError.noteNotFound
                case .resourceExhausted:
                    throw ShareError.rateLimitExceeded
                default:
                    throw ShareError.serverError(error.localizedDescription)
                }
            }
            
            throw error
        }
    }
    
    // MARK: - Revoke Share Access
    
    /// Revoke share access for specific users
    func revokeAccess(for note: ChurchNote, fromUserIds userIds: [String]) async throws -> RevokeResult {
        guard let noteId = note.id else {
            throw ShareError.invalidNote
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        let callable = functions.httpsCallable("revokeChurchNoteShare")
        
        let data: [String: Any] = [
            "noteId": noteId,
            "userIds": userIds
        ]
        
        do {
            let result = try await callable.call(data)
            
            guard let resultData = result.data as? [String: Any],
                  let success = resultData["success"] as? Bool,
                  let revokedCount = resultData["revokedCount"] as? Int else {
                throw ShareError.invalidResponse
            }
            
            print("✅ Revoked access for \(revokedCount) users")
            
            return RevokeResult(
                success: success,
                revokedCount: revokedCount
            )
        } catch let error as NSError {
            print("❌ Revoke access error: \(error)")
            
            if error.domain == FunctionsErrorDomain {
                let code = FunctionsErrorCode(rawValue: error.code)
                
                switch code {
                case .unauthenticated:
                    throw ShareError.notAuthenticated
                case .permissionDenied:
                    throw ShareError.permissionDenied
                case .notFound:
                    throw ShareError.noteNotFound
                default:
                    throw ShareError.serverError(error.localizedDescription)
                }
            }
            
            throw error
        }
    }
    
    // MARK: - Generate Share Link
    
    /// Generate a shareable link for a church note
    func generateShareLink(for note: ChurchNote) async throws -> ShareLinkResult {
        guard let noteId = note.id else {
            throw ShareError.invalidNote
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        let callable = functions.httpsCallable("generateChurchNoteShareLink")
        
        let data: [String: Any] = [
            "noteId": noteId
        ]
        
        do {
            let result = try await callable.call(data)
            
            guard let resultData = result.data as? [String: Any],
                  let success = resultData["success"] as? Bool,
                  let shareUrl = resultData["shareUrl"] as? String,
                  let shareLinkId = resultData["shareLinkId"] as? String else {
                throw ShareError.invalidResponse
            }
            
            print("✅ Generated share link: \(shareUrl)")
            
            return ShareLinkResult(
                success: success,
                shareUrl: shareUrl,
                shareLinkId: shareLinkId
            )
        } catch let error as NSError {
            print("❌ Generate share link error: \(error)")
            
            if error.domain == FunctionsErrorDomain {
                let code = FunctionsErrorCode(rawValue: error.code)
                
                switch code {
                case .unauthenticated:
                    throw ShareError.notAuthenticated
                case .permissionDenied:
                    throw ShareError.permissionDenied
                case .notFound:
                    throw ShareError.noteNotFound
                default:
                    throw ShareError.serverError(error.localizedDescription)
                }
            }
            
            throw error
        }
    }
}

// MARK: - Result Models

struct ShareResult {
    let success: Bool
    let sharedWithCount: Int
    let sharedWith: [String]
}

struct RevokeResult {
    let success: Bool
    let revokedCount: Int
}

struct ShareLinkResult {
    let success: Bool
    let shareUrl: String
    let shareLinkId: String
}

// MARK: - Errors

enum ShareError: LocalizedError {
    case invalidNote
    case invalidResponse
    case notAuthenticated
    case permissionDenied
    case noteNotFound
    case rateLimitExceeded
    case serverError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidNote:
            return "Invalid note. The note must be saved before sharing."
        case .invalidResponse:
            return "Invalid response from server."
        case .notAuthenticated:
            return "You must be signed in to share notes."
        case .permissionDenied:
            return "You don't have permission to share this note."
        case .noteNotFound:
            return "Note not found."
        case .rateLimitExceeded:
            return "Too many share requests. Please wait a moment and try again."
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}
