//
//  PulseActionRouter.swift
//  AMEN — Amen Pulse
//
//  Routes a card's single primary action. Every Pulse card has exactly one verb;
//  success is "task completed and app closed," not session length.
//
//  Routing:
//   • amen:// (or amenapp://) deeplink → in-app navigation via DeepLinkRouter
//     (reliable + Shabbat-gated). Backend cards carry these — e.g.
//     amen://prayer/{id}, amen://user/{id}, amen://event/{id}, amen://space/{id}.
//   • http(s) deeplink → opened in the system/in-app browser.
//   • No routable deeplink → the verb is DISABLED in the UI (see canRoute). There
//     is no silent fallback: fail-closed (do nothing visible) beats fail-silent
//     (a pill that lands nowhere).
//

import SwiftUI
import UIKit

@MainActor
final class PulseActionRouter {
    static let shared = PulseActionRouter()
    private init() {}

    /// Whether this card's action resolves to a real destination. The UI uses
    /// this to hide/disable verbs that would otherwise land nowhere.
    func canRoute(_ card: PulseCard) -> Bool {
        guard let link = card.action.deeplink, let url = URL(string: link) else { return false }
        switch url.scheme?.lowercased() {
        case "amen", "amenapp": return DeepLinkRouter.shared.parse(url: url) != nil
        case "http", "https":   return true
        default:                return false
        }
    }

    /// Performs the card's single action. No-ops if the card isn't routable.
    func route(_ card: PulseCard) {
        guard let link = card.action.deeplink, let url = URL(string: link) else { return }

        switch url.scheme?.lowercased() {
        case "amen", "amenapp":
            guard let route = DeepLinkRouter.shared.parse(url: url) else { return }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            DeepLinkRouter.shared.navigate(to: route)
        case "http", "https":
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            UIApplication.shared.open(url)
        default:
            return
        }
    }
}
