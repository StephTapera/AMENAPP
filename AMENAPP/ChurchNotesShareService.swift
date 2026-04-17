//
//  ChurchNotesShareService.swift
//  AMENAPP
//
//  Client-side service for calling Church Notes sharing Cloud Functions
//

import Foundation
import Combine
import FirebaseFunctions
import UIKit

@MainActor
class ChurchNotesShareService: ObservableObject {
    static let shared = ChurchNotesShareService()
    
    @Published var isProcessing = false
    @Published var lastError: Error?
    
    private lazy var functions = Functions.functions()
    
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
            
            dlog("✅ Note shared with \(sharedWithCount) users")
            
            return ShareResult(
                success: success,
                sharedWithCount: sharedWithCount,
                sharedWith: sharedWith
            )
        } catch let error as NSError {
            dlog("❌ Share note error: \(error)")
            
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
            
            dlog("✅ Revoked access for \(revokedCount) users")
            
            return RevokeResult(
                success: success,
                revokedCount: revokedCount
            )
        } catch let error as NSError {
            dlog("❌ Revoke access error: \(error)")
            
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
            
            dlog("✅ Generated share link: \(shareUrl)")
            
            return ShareLinkResult(
                success: success,
                shareUrl: shareUrl,
                shareLinkId: shareLinkId
            )
        } catch let error as NSError {
            dlog("❌ Generate share link error: \(error)")
            
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

// MARK: - Feature 9: Share Selected Content + Testimony Draft

extension ChurchNotesShareService {

    /// Share a specific selected passage from a note (not the whole note).
    /// Opens the system share sheet with the selection and a note attribution line.
    func shareSelectedContent(text: String, from note: ChurchNote) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let df = DateFormatter(); df.dateStyle = .medium
        var attribution = "— from my notes"
        if let church = note.churchName, !church.isEmpty {
            attribution += " at \(church)"
        }
        attribution += " (\(df.string(from: note.date)))"
        if let ref = note.scripture, !ref.isEmpty {
            attribution += "\n\(ref)"
        }

        let shareText = "\"\(text)\"\n\n\(attribution)"

        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes
                    .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
                  let rootVC = windowScene.windows.first?.rootViewController else { return }

            let activityVC = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
            activityVC.popoverPresentationController?.sourceView = rootVC.view
            rootVC.present(activityVC, animated: true)
        }
    }

    /// Formats a church note as a first-person testimony draft.
    /// Returns a string the user can edit before sharing to social or the feed.
    func convertToTestimonyDraft(note: ChurchNote) -> String {
        let df = DateFormatter(); df.dateStyle = .long
        var draft = ""

        draft += "I want to share something that moved me in worship "
        if let church = note.churchName, !church.isEmpty {
            draft += "at \(church) "
        }
        draft += "on \(df.string(from: note.date)).\n\n"

        if let sermon = note.sermonTitle, !sermon.isEmpty {
            draft += "The message \"\(sermon)\" "
        } else {
            draft += "The message "
        }
        if let pastor = note.pastor, !pastor.isEmpty {
            draft += "by \(pastor) "
        }
        draft += "really spoke to my heart.\n\n"

        // Pull first meaningful paragraph from content
        let paragraphs = note.content
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 40 }
        if let first = paragraphs.first {
            let snippet = first.count > 200 ? String(first.prefix(197)) + "..." : first
            draft += snippet + "\n\n"
        }

        // Add scripture
        if let ref = note.scripture, !ref.isEmpty {
            draft += "\"\(ref)\" has been on my heart since.\n\n"
        } else if let ref = note.scriptureReferences.first {
            draft += "\(ref) has been on my heart since.\n\n"
        }

        // Key point call-to-action
        if let kp = note.keyPoints.first {
            draft += "One thing I'm taking with me: \(kp)\n\n"
        }

        draft += "Has God been speaking to you about something similar? I'd love to hear your story."
        return draft
    }
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
