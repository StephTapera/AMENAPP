import UIKit

// MARK: - Instagram Stories

/// Shares a 1080×1920 Story card to Instagram Stories via URL scheme + pasteboard.
/// Falls back to system share sheet when Instagram is not installed.
/// Requires `instagram-stories` in `LSApplicationQueriesSchemes` (Info.plist).
// TODO(Info.plist): Add "instagram-stories", "instagram", "fb-stories", "facebook",
//                  "fb-messenger", "whatsapp" to LSApplicationQueriesSchemes.
@MainActor
enum InstagramStoryShare {

    static func share(_ content: ShareContent) async {
        let schemeURL = URL(string: "instagram-stories://share")!
        guard UIApplication.shared.canOpenURL(schemeURL) else {
            ShareService.presentSystemSheet(for: content)
            return
        }

        guard let card = renderCard(content) else {
            ShareService.presentSystemSheet(for: content)
            return
        }

        let bundleId = Bundle.main.bundleIdentifier ?? "com.amen.app"
        let pasteboardItems: [String: Any] = [
            "com.instagram.sharedSticker.backgroundImage": card,
            "com.instagram.sharedSticker.contentURL": content.postURL.absoluteString,
        ]

        UIPasteboard.general.setItems([pasteboardItems], options: [
            .expirationDate: Date().addingTimeInterval(300) // 5-min expiry
        ])

        if let target = URL(string: "instagram-stories://share?source_application=\(bundleId)") {
            await UIApplication.shared.open(target)
        }
    }

    private static func renderCard(_ content: ShareContent) -> Data? {
        guard let image = ShareCardRenderer.renderImage(
            post: content.post,
            size: .story,
            pullQuote: content.pullQuote,
            verseRef: content.verseRef,
            authorAvatar: content.authorAvatar
        ) else { return nil }
        return image.pngData()
    }
}

// MARK: - Facebook Stories

/// Shares a Story card to Facebook Stories.
/// Falls back to system share sheet when Facebook is not installed.
/// Requires `fb-stories` in `LSApplicationQueriesSchemes` (Info.plist).
@MainActor
enum FacebookStoryShare {

    static func share(_ content: ShareContent) async {
        let schemeURL = URL(string: "fb-stories://share")!
        guard UIApplication.shared.canOpenURL(schemeURL) else {
            ShareService.presentSystemSheet(for: content)
            return
        }

        guard let card = renderCard(content) else {
            ShareService.presentSystemSheet(for: content)
            return
        }

        let pasteboardItems: [String: Any] = [
            "com.facebook.sharedSticker.backgroundImage": card,
        ]

        UIPasteboard.general.setItems([pasteboardItems], options: [
            .expirationDate: Date().addingTimeInterval(300)
        ])

        if let target = URL(string: "fb-stories://share") {
            await UIApplication.shared.open(target)
        }
    }

    private static func renderCard(_ content: ShareContent) -> Data? {
        guard let image = ShareCardRenderer.renderImage(
            post: content.post,
            size: .story,
            pullQuote: content.pullQuote,
            verseRef: content.verseRef,
            authorAvatar: content.authorAvatar
        ) else { return nil }
        return image.pngData()
    }
}
