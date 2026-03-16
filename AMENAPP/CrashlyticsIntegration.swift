//
//  CrashlyticsIntegration.swift
//  AMENAPP
//
//  Feature 55: Full Crashlytics integration with custom keys,
//  breadcrumbs, and non-fatal error logging.
//

import Foundation
import FirebaseAuth
import FirebaseCrashlytics

enum CrashlyticsIntegration {

    // MARK: - User Context

    /// Set user context on every auth state change.
    static func setUserContext() {
        let crashlytics = Crashlytics.crashlytics()
        if let user = Auth.auth().currentUser {
            crashlytics.setUserID(user.uid)
            crashlytics.setCustomValue(user.email ?? "none", forKey: "email")
            crashlytics.setCustomValue(user.displayName ?? "none", forKey: "displayName")
        } else {
            crashlytics.setUserID("signed_out")
        }
    }

    // MARK: - Screen Tracking (Breadcrumbs)

    /// Log a navigation breadcrumb.
    static func logScreen(_ screenName: String) {
        Crashlytics.crashlytics().setCustomValue(screenName, forKey: "current_screen")
        Crashlytics.crashlytics().log("Screen: \(screenName)")
    }

    /// Log a user action breadcrumb.
    static func logAction(_ action: String) {
        Crashlytics.crashlytics().setCustomValue(action, forKey: "last_action")
        Crashlytics.crashlytics().log("Action: \(action)")
    }

    // MARK: - Non-Fatal Error Logging

    /// Log a non-fatal Firestore error.
    static func logFirestoreError(_ error: Error, context: String) {
        let nsError = error as NSError
        Crashlytics.crashlytics().setCustomValue(context, forKey: "firestore_context")
        Crashlytics.crashlytics().setCustomValue(nsError.code, forKey: "firestore_error_code")
        Crashlytics.crashlytics().record(error: error, userInfo: [
            "context": context,
            "code": nsError.code,
            "domain": nsError.domain,
        ])
    }

    /// Log a non-fatal network error.
    static func logNetworkError(_ error: Error, endpoint: String) {
        Crashlytics.crashlytics().setCustomValue(endpoint, forKey: "failed_endpoint")
        Crashlytics.crashlytics().record(error: error, userInfo: [
            "endpoint": endpoint,
        ])
    }

    /// Log a non-fatal auth error.
    static func logAuthError(_ error: Error, flow: String) {
        Crashlytics.crashlytics().setCustomValue(flow, forKey: "auth_flow")
        Crashlytics.crashlytics().record(error: error, userInfo: [
            "flow": flow,
        ])
    }

    // MARK: - Custom Keys

    /// Set app state for crash context.
    static func setAppState(key: String, value: String) {
        Crashlytics.crashlytics().setCustomValue(value, forKey: key)
    }
}
