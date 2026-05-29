//
//  Error+UserFriendly.swift
//  AMENAPP
//
//  Maps technical Firebase / system errors to human-readable strings.
//  Use `error.userFriendlyMessage` anywhere a message will be shown to the user
//  instead of `error.localizedDescription`, which can expose internal SDK details.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

extension Error {
    /// A short, user-facing description that hides internal SDK details.
    /// Falls back to a generic "Something went wrong" message rather than
    /// exposing raw Firebase error codes or system strings.
    var userFriendlyMessage: String {
        let nsError = self as NSError

        // ── Firebase Auth errors ────────────────────────────────────────────
        if nsError.domain == AuthErrorDomain {
            switch nsError.code {
            case AuthErrorCode.networkError.rawValue:
                return "Check your internet connection and try again."
            case AuthErrorCode.userNotFound.rawValue:
                return "No account found with that email."
            case AuthErrorCode.wrongPassword.rawValue,
                 AuthErrorCode.invalidCredential.rawValue:
                return "Incorrect email or password."
            case AuthErrorCode.emailAlreadyInUse.rawValue:
                return "An account with that email already exists."
            case AuthErrorCode.weakPassword.rawValue:
                return "Please choose a stronger password (at least 6 characters)."
            case AuthErrorCode.invalidEmail.rawValue:
                return "That doesn't look like a valid email address."
            case AuthErrorCode.tooManyRequests.rawValue:
                return "Too many attempts. Please wait a moment and try again."
            case AuthErrorCode.userDisabled.rawValue:
                return "This account has been disabled. Contact support for help."
            case AuthErrorCode.requiresRecentLogin.rawValue:
                return "For security, please sign in again before making this change."
            default:
                break
            }
        }

        // ── Firestore errors ────────────────────────────────────────────────
        if nsError.domain == FirestoreErrorDomain,
           let code = FirestoreErrorCode.Code(rawValue: nsError.code) {
            switch code {
            case .permissionDenied:
                return "You don't have permission to do that."
            case .unavailable:
                return "Service temporarily unavailable. Try again in a moment."
            case .notFound:
                return "The content you're looking for no longer exists."
            case .aborted, .cancelled:
                return "The request was cancelled. Please try again."
            case .resourceExhausted:
                return "Too many requests. Please wait a moment and try again."
            case .unauthenticated:
                return "Please sign in to continue."
            default:
                break
            }
        }

        // ── Network / URL errors ────────────────────────────────────────────
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorNetworkConnectionLost:
                return "Check your internet connection and try again."
            case NSURLErrorTimedOut:
                return "The request timed out. Please try again."
            default:
                break
            }
        }

        // ── Swift cancellation ──────────────────────────────────────────────
        if self is CancellationError {
            return "The request was cancelled."
        }

        return "Something went wrong. Please try again."
    }
}
