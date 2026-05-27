import UIKit
import SwiftUI

// MARK: - PUBLIC INTERFACE

/// Central share orchestrator for story-card sharing (Instagram, Facebook, system sheet).
/// All methods are `@MainActor` because `UIApplication.shared` and `UIPasteboard`
/// must be accessed on the main thread.
@MainActor
enum ShareService {

    // MARK: - Public API

    static func share(
        _ content: ShareContent,
        to destination: StoryShareTarget
    ) async {
        switch destination {
        case .instagramStory:
            await InstagramStoryShare.share(content)
        case .facebookStory:
            await FacebookStoryShare.share(content)
        case .messages, .whatsapp:
            presentSystemSheet(for: content)
        case .copyLink:
            copyLink(for: content)
        case .systemSheet:
            presentSystemSheet(for: content)
        }
    }

    /// Presents the native iOS system share sheet.
    static func presentSystemSheet(for content: ShareContent, anchor: UIView? = nil) {
        var items: [Any] = []
        if let caption = content.caption, !caption.isEmpty {
            items.append(caption)
        }
        items.append(content.postURL)

        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        let presenter = topViewController()
        if let anchor {
            vc.popoverPresentationController?.sourceView = anchor
            vc.popoverPresentationController?.sourceRect = anchor.bounds
        } else if let presenter {
            vc.popoverPresentationController?.sourceView = presenter.view
            vc.popoverPresentationController?.sourceRect = CGRect(
                x: presenter.view.bounds.midX, y: presenter.view.bounds.maxY,
                width: 0, height: 0
            )
        }
        presenter?.present(vc, animated: true)
    }

    /// Returns whether the device can open the given destination (i.e. app is installed).
    static func canShare(to destination: StoryShareTarget) -> Bool {
        switch destination {
        case .instagramStory:
            return canOpen("instagram-stories://share")
        case .facebookStory:
            return canOpen("fb-stories://share")
        case .messages:
            return canOpen("sms://")
        case .whatsapp:
            return canOpen("whatsapp://")
        case .copyLink, .systemSheet:
            return true
        }
    }

    // MARK: - Private helpers

    private static func copyLink(for content: ShareContent) {
        UIPasteboard.general.string = content.postURL.absoluteString
        HapticManager.impact(style: .light)
        ToastManager.shared.success("Link copied")
    }

    private static func canOpen(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    static func topViewController() -> UIViewController? {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
