//
//  EnforcementService.swift
//  AMENAPP
//
//  Feature 7 — Structured moderation responses.
//
//  Reads a user's active enforcement record from Firestore
//  `user_enforcement/{uid}` and exposes a dismissible nudge banner
//  message that CreatePostView injects at compose-time.
//
//  Firestore schema (user_enforcement/{uid}):
//    isActive: Bool          — true while enforcement is in effect
//    level: String           — "nudge" | "warning" | "restricted"
//    message: String         — human-readable explanation shown in banner
//    expiresAt: Timestamp?   — nil = permanent until manually lifted
//    reason: String?         — optional internal reason code
//
//  Only "nudge" and "warning" levels surface a dismissible banner.
//  "restricted" level blocks posting entirely and redirects to a
//  read-only enforcement detail sheet (future implementation).
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class EnforcementService: ObservableObject {
    static let shared = EnforcementService()
    private init() {}

    // MARK: - Types

    enum EnforcementLevel: String {
        case nudge      = "nudge"
        case warning    = "warning"
        case restricted = "restricted"
    }

    struct EnforcementRecord {
        let level: EnforcementLevel
        let message: String
        let expiresAt: Date?
    }

    // MARK: - Published State

    /// Non-nil when the current user has an active enforcement record.
    @Published private(set) var activeRecord: EnforcementRecord?

    // MARK: - Fetch

    /// Fetches the current user's enforcement record once.
    /// Called from CreatePostView.onAppear.
    func fetchIfNeeded() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        do {
            let doc = try await Firestore.firestore()
                .collection("user_enforcement")
                .document(uid)
                .getDocument()

            guard let data = doc.data(),
                  data["isActive"] as? Bool == true,
                  let levelRaw = data["level"] as? String,
                  let level = EnforcementLevel(rawValue: levelRaw),
                  let message = data["message"] as? String else {
                activeRecord = nil
                return
            }

            // Skip if expired
            if let expiryTs = data["expiresAt"] as? Timestamp,
               expiryTs.dateValue() < Date() {
                activeRecord = nil
                return
            }

            activeRecord = EnforcementRecord(
                level: level,
                message: message,
                expiresAt: (data["expiresAt"] as? Timestamp)?.dateValue()
            )
        } catch {
            // Non-fatal — silently skip if doc doesn't exist or network fails
            activeRecord = nil
        }
    }

    /// Called when user dismisses the banner (nudge/warning levels only).
    func dismissBanner() {
        // Only clear nudge/warning from UI; record stays in Firestore
        if activeRecord?.level != .restricted {
            activeRecord = nil
        }
    }

    /// Convenience: true when the user's posting should be fully blocked.
    var isPostingBlocked: Bool {
        activeRecord?.level == .restricted
    }

    /// Nudge message to show in CreatePostView's banner, if any.
    var nudgeMessage: String? {
        guard let rec = activeRecord, rec.level != .restricted else { return nil }
        return rec.message
    }
}
