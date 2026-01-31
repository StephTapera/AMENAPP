//
//  MessagingError.swift
//  AMENAPP
//
//  Comprehensive error handling for messaging system
//

import SwiftUI

enum MessagingError: Identifiable, LocalizedError {
    case sendFailed(String)
    case muteFailed
    case pinFailed
    case archiveFailed
    case deleteFailed
    case loadFailed
    case networkError
    case permissionDenied
    case userBlocked
    case invalidInput(String)
    case tooManyRequests
    case photoUploadFailed
    case groupCreationFailed(String)
    case searchFailed
    
    var id: String {
        switch self {
        case .sendFailed(let reason): return "sendFailed_\(reason)"
        case .muteFailed: return "muteFailed"
        case .pinFailed: return "pinFailed"
        case .archiveFailed: return "archiveFailed"
        case .deleteFailed: return "deleteFailed"
        case .loadFailed: return "loadFailed"
        case .networkError: return "networkError"
        case .permissionDenied: return "permissionDenied"
        case .userBlocked: return "userBlocked"
        case .invalidInput(let reason): return "invalidInput_\(reason)"
        case .tooManyRequests: return "tooManyRequests"
        case .photoUploadFailed: return "photoUploadFailed"
        case .groupCreationFailed(let reason): return "groupCreationFailed_\(reason)"
        case .searchFailed: return "searchFailed"
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .sendFailed(let reason):
            return "Failed to send message: \(reason)"
        case .muteFailed:
            return "Failed to mute conversation"
        case .pinFailed:
            return "Failed to pin conversation"
        case .archiveFailed:
            return "Failed to archive conversation"
        case .deleteFailed:
            return "Failed to delete conversation"
        case .loadFailed:
            return "Failed to load messages"
        case .networkError:
            return "No internet connection"
        case .permissionDenied:
            return "You don't have permission to perform this action"
        case .userBlocked:
            return "You cannot message this user"
        case .invalidInput(let reason):
            return "Invalid input: \(reason)"
        case .tooManyRequests:
            return "You're sending messages too quickly"
        case .photoUploadFailed:
            return "Failed to upload photo"
        case .groupCreationFailed(let reason):
            return "Failed to create group: \(reason)"
        case .searchFailed:
            return "Failed to search users"
        }
    }
    
    var canRetry: Bool {
        switch self {
        case .sendFailed, .networkError, .loadFailed, .photoUploadFailed, .searchFailed:
            return true
        case .tooManyRequests:
            return false // Need to wait
        default:
            return false
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .networkError:
            return "Please check your internet connection and try again"
        case .sendFailed:
            return "Tap to retry sending"
        case .permissionDenied:
            return "Contact support if you think this is a mistake"
        case .userBlocked:
            return "Unblock this user to send messages"
        case .tooManyRequests:
            return "Please wait a moment before sending more messages"
        case .photoUploadFailed:
            return "Try selecting a different photo or check your connection"
        default:
            return "Please try again"
        }
    }
    
    var icon: String {
        switch self {
        case .networkError:
            return "wifi.slash"
        case .sendFailed, .loadFailed:
            return "exclamationmark.circle"
        case .permissionDenied, .userBlocked:
            return "hand.raised"
        case .tooManyRequests:
            return "clock.badge.exclamationmark"
        case .photoUploadFailed:
            return "photo.badge.exclamationmark"
        default:
            return "exclamationmark.triangle"
        }
    }
}

// MARK: - Error Alert Modifier

struct MessagingErrorAlert: ViewModifier {
    @Binding var error: MessagingError?
    var onRetry: (() -> Void)?
    
    func body(content: Content) -> some View {
        content
            .alert(item: $error) { error in
                if error.canRetry, let retry = onRetry {
                    return Alert(
                        title: Text("Error"),
                        message: Text("\(error.errorDescription ?? "Unknown error")\n\n\(error.recoverySuggestion ?? "")"),
                        primaryButton: .default(Text("Retry"), action: retry),
                        secondaryButton: .cancel()
                    )
                } else {
                    return Alert(
                        title: Text("Error"),
                        message: Text("\(error.errorDescription ?? "Unknown error")\n\n\(error.recoverySuggestion ?? "")"),
                        dismissButton: .default(Text("OK"))
                    )
                }
            }
    }
}

extension View {
    func messagingErrorAlert(error: Binding<MessagingError?>, onRetry: (() -> Void)? = nil) -> some View {
        modifier(MessagingErrorAlert(error: error, onRetry: onRetry))
    }
}
