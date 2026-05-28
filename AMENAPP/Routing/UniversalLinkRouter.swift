import Foundation
import SwiftUI
import FirebaseAuth

// MARK: - PUBLIC INTERFACE

/// Handles inbound Universal Links (`https://amen.app/post/*`) and
/// custom scheme URLs (`amen://post/{id}`, `amen://draft/from-share`).
///
/// Wire up in `AMENAPPApp`:
/// ```swift
/// .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
///     UniversalLinkRouter.shared.handleUserActivity(activity)
/// }
/// .onOpenURL { url in
///     UniversalLinkRouter.shared.handle(url: url)
/// }
/// ```
@MainActor
public final class UniversalLinkRouter: ObservableObject {
    public static let shared = UniversalLinkRouter()

    private init() {}

    // MARK: - Entry points

    /// Returns `true` if the URL was handled.
    @discardableResult
    public func handle(url: URL) -> Bool {
        if let scheme = url.scheme?.lowercased() {
            if scheme == "amen" {
                return handleCustomScheme(url)
            }
        }
        if url.host == "amen.app" || url.host == "www.amen.app" {
            return handleWebURL(url)
        }
        return false
    }

    /// Returns `true` if the user activity was handled (Universal Link tap).
    @discardableResult
    public func handleUserActivity(_ activity: NSUserActivity) -> Bool {
        guard activity.activityType == NSUserActivityTypeBrowsingWeb,
              let webURL = activity.webpageURL
        else { return false }
        return handle(url: webURL)
    }

    // MARK: - Private routing

    private func handleWebURL(_ url: URL) -> Bool {
        let path = url.path
        if path.hasPrefix("/post/") {
            let postId = String(path.dropFirst("/post/".count))
                .components(separatedBy: "/").first ?? ""
            if !postId.isEmpty { navigateToPost(postId); return true }
        }
        if path.hasPrefix("/user/") {
            let userId = String(path.dropFirst("/user/".count))
                .components(separatedBy: "/").first ?? ""
            if !userId.isEmpty { navigateToUser(userId); return true }
        }
        if path.hasPrefix("/verse/") {
            let ref = String(path.dropFirst("/verse/".count))
                .components(separatedBy: "/").first ?? ""
            if !ref.isEmpty { navigateToVerse(ref); return true }
        }
        return false
    }

    private func handleCustomScheme(_ url: URL) -> Bool {
        let host = url.host ?? ""

        // amen://post/{id}
        if host == "post" {
            let postId = url.pathComponents.dropFirst().first ?? ""
            if !postId.isEmpty { navigateToPost(postId); return true }
        }

        // amen://user/{userId}
        if host == "user" {
            let userId = url.pathComponents.dropFirst().first ?? ""
            if !userId.isEmpty { navigateToUser(userId); return true }
        }

        // amen://verse/{reference}  e.g. amen://verse/John-3-16
        if host == "verse" {
            let ref = url.pathComponents.dropFirst().first ?? ""
            if !ref.isEmpty { navigateToVerse(ref); return true }
        }

        // amen://draft/from-share  (inbound from Share Extension)
        if host == "draft" && url.pathComponents.contains("from-share") {
            handleShareDraft()
            return true
        }

        return false
    }

    private func navigateToPost(_ postId: String) {
        guard Auth.auth().currentUser != nil else { return }
        NotificationDeepLinkRouter.shared.verifyAndNavigate(to: .post(postId: postId))
    }

    private func navigateToUser(_ userId: String) {
        guard Auth.auth().currentUser != nil else { return }
        NotificationDeepLinkRouter.shared.verifyAndNavigate(to: .profile(userId: userId))
    }

    private func navigateToVerse(_ reference: String) {
        guard Auth.auth().currentUser != nil else { return }
        NotificationCenter.default.post(
            name: .amenOpenVerse,
            object: nil,
            userInfo: ["verseReference": reference]
        )
    }

    private func handleShareDraft() {
        let draft = PendingDraftLoader.consume()
        NotificationCenter.default.post(
            name: .amenOpenShareDraft,
            object: nil,
            userInfo: draft.map { ["draft": $0] } ?? [:]
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when a verse deep-link arrives (`amen://verse/{reference}` or
    /// `https://amen.app/verse/{reference}`). SelahView / BibleEngine observers
    /// read `userInfo["verseReference"]` (a percent-encoded reference string,
    /// e.g. "John-3-16") to open the correct passage.
    static let amenOpenVerse = Notification.Name("amenOpenVerse")
}
